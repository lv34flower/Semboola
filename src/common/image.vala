/* image.vala
 *
 * Copyright 2025 v34
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */


public class ImageControl : Object {

    public const int THUMB_WIDTH = 80;
    public const int THUMB_HEIGHT = 80;
    // 画像ダウンロードの並列上限
    private const int MAX_PARALLEL_IMAGE_DOWNLOADS = 4;

    // 待ち行列
    private Gee.Queue<ImageDownloadTask> image_download_queue = new Gee.LinkedList<ImageDownloadTask> ();

    // 現在動いているダウンロード数
    private int running_image_downloads = 0;

    // 画像ダウンロードタスク
    private class ImageDownloadTask : Object {
        public string url;
        public weak Gtk.Picture thumb;

        public ImageDownloadTask (string url, Gtk.Picture thumb) {
            this.url = url;
            this.thumb = thumb;
        }
    }

    // 「画像URL」を全部返す
    public Gee.ArrayList<string> find_image_urls_for_post (ResRow.ResItem post) {
        var result = new Gee.ArrayList<string> ();

        var spans = post.get_spans ();
        if (spans == null)
            return result;

        foreach (var span in spans) {
            if (span.type == SpanType.URL && span.payload != null) {
                var url = span.payload;
                if (is_image_url (url)) {
                    result.add (url);
                }
            }
        }

        return result;
    }

    // 画像キャッシュ用のパスを作る
    public string get_image_cache_path (string url) {
        // ~/.cache/Semboola/thumbs
        var cache_root = Environment.get_user_cache_dir ();
        var dir = Path.build_filename (cache_root, "Semboola", "thumbs");

        try {
            DirUtils.create_with_parents (dir, 0755);
        } catch (Error e) {
            // 作れなかったら諦めてキャッシュ無しで続行
        }

        // 拡張子を元URLから取り出す（? # 以降は除外）
        string lower = url.down ();
        int q = lower.index_of_char ('?');
        if (q >= 0)
            lower = lower.substring (0, q);
        int hash = lower.index_of_char ('#');
        if (hash >= 0)
            lower = lower.substring (0, hash);

        string ext = ".img";
        int dot = lower.last_index_of (".");
        if (dot >= 0 && dot + 1 < lower.length) {
            ext = lower.substring (dot);
            if (!(ext == ".jpg" || ext == ".jpeg" || ext == ".png" || ext == ".gif")) {
                ext = ".img";
            }
        }

        // URL を SHA256 でハッシュしてファイル名にする
        var checksum = new Checksum (ChecksumType.SHA256);
        checksum.update (url.data, (size_t) url.length);
        var hex = checksum.get_string ();

        return Path.build_filename (dir, hex + ext);
    }

    // サムネ画像を非同期でロード（キャッシュ付き）して thumb Picture にセット
    public async void load_image_thumbnail_async (string url, Gtk.Picture thumb, bool force=false) {
        try {
            var cache_path = get_image_cache_path (url);
            Gdk.Pixbuf? pixbuf_for_thumb = null;

            // 1. キャッシュからサムネ用 Pixbuf を作る
            if (FileUtils.test (cache_path, FileTest.EXISTS)) {
                try {
                    var original = new Gdk.Pixbuf.from_file (cache_path);
                    pixbuf_for_thumb = scale_pixbuf_for_thumb (original);
                } catch (Error e) {
                    pixbuf_for_thumb = null;
                }
            }

            // 2. キャッシュが無い場合はダウンロードして保存 → 縮小
            if (pixbuf_for_thumb == null) {
                var client = new FiveCh.Client ();

                // HEAD でサイズチェック
                var head_msg = new Soup.Message ("HEAD", url);
                yield client.session.send_async (head_msg, Priority.DEFAULT, null);

                if (head_msg.get_status () != Soup.Status.OK) {
                    // HEAD でエラーなら諦める
                    return;
                }

                // Content-Length を取得
                int64 content_length = head_msg.response_headers.get_content_length ();

                // Content-Length が 0以下（不明or0）または上限超えなら捨てる
                // force==trueなら捨てない
                if (!force) {
                    if (content_length <= 0 || content_length > 1 * 1024 * 1024) {
                        // ここで return すればサムネ無しで終わり
                        return;
                    }
                }

                var msg = new Soup.Message ("GET", url);

                var bytes = yield client.session.send_and_read_async (msg, Priority.DEFAULT, null);
                if (msg.get_status () != Soup.Status.OK)
                    return;

                unowned uint8[] data = bytes.get_data ();

                // キャッシュ保存
                try {
                    FileUtils.set_data (cache_path, data);
                } catch (Error e) {
                }

                // PixbufLoaderで画像として解釈
                var loader = new Gdk.PixbufLoader ();
                loader.write (data);
                loader.close ();

                var original = loader.get_pixbuf ();
                if (original == null)
                    return;

                pixbuf_for_thumb = scale_pixbuf_for_thumb (original);
            }

            if (pixbuf_for_thumb == null)
                return;

            // サムネ用テクスチャ作成
            var texture_thumb = Gdk.Texture.for_pixbuf (pixbuf_for_thumb);
            thumb.set_paintable (texture_thumb);

        } catch (Error e) {
            // 失敗時は何も表示しない
        }
    }

    // Pixbuf をサムネ用に縮小して返す
    public Gdk.Pixbuf scale_pixbuf_for_thumb (Gdk.Pixbuf src) {
        int w = src.get_width ();
        int h = src.get_height ();

        if (w <= 0 || h <= 0)
            return src;

        // 目標サイズに収まるようにスケール
        double scale_w = (double) THUMB_WIDTH / (double) w;
        double scale_h = (double) THUMB_HEIGHT / (double) h;
        double scale = Math.fmin (1.0, Math.fmin (scale_w, scale_h)); // 拡大はしない

        int new_w = (int) Math.round (w * scale);
        int new_h = (int) Math.round (h * scale);

        if (new_w <= 0 || new_h <= 0)
            return src;

        return src.scale_simple (new_w, new_h, Gdk.InterpType.BILINEAR);
    }

    // ダウンロードタスクをキューに積む
    public void enqueue_image_download (string url, Gtk.Picture thumb) {
        image_download_queue.offer (new ImageDownloadTask (url, thumb));
        process_image_download_queue ();
    }

    // キューを処理して、同時実行数の上限まで流す
    public void process_image_download_queue () {
        // すでに上限まで動いていたら何もしない
        while (running_image_downloads < MAX_PARALLEL_IMAGE_DOWNLOADS &&
               !image_download_queue.is_empty) {

            var task = image_download_queue.poll ();
            if (task == null)
                break;

            if (task.thumb == null)
                continue;

            running_image_downloads++;

            // async 関数を begin して、終わったらカウンタを戻す
            load_image_thumbnail_async.begin (task.url, task.thumb, false, (obj, res) => {
                try {
                    load_image_thumbnail_async.end (res);
                } catch (Error e) {
                    // 画像ロード失敗は
                }

                running_image_downloads--;
                // 次のタスクを回す
                process_image_download_queue ();
            });
        }
    }

    // 画像 URL かどうか判定（拡張子ベース）
    private static bool is_image_url (string url) {
        if (url == null)
            return false;

        // クエリ・フラグメントは切り捨ててから判定
        string lower = url.down ();
        int q = lower.index_of_char ('?');
        if (q >= 0)
            lower = lower.substring (0, q);
        int hash = lower.index_of_char ('#');
        if (hash >= 0)
            lower = lower.substring (0, hash);

        return lower.has_suffix (".jpg")
            || lower.has_suffix (".jpeg")
            || lower.has_suffix (".png")
            || lower.has_suffix (".gif");
    }
}

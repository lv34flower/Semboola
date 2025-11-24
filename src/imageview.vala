/* imageview.vala
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

using Gtk;
using GLib;
using Adw;

[GtkTemplate (ui = "/jp/lv34/Semboola/imageview.ui")]
public class imageview : Adw.NavigationPage {
    private string name;
    private string path;

    private bool initial_fit_done = false;
    private double zoom = 1.0;

    // ジェスチャ中での scale 管理
    private double last_scale = 1.0;          // 直前の scale
    private double gesture_base_zoom = 1.0;   // ジェスチャ開始時の zoom

    // ピンチ中心（ジェスチャ開始時に1回だけ決める）
    private double gesture_center_x = 0.0;
    private double gesture_center_y = 0.0;

    private int original_width = 0;
    private int original_height = 0;

    Semboola.Window win;

    [GtkChild]
    unowned Gtk.Picture picture;
    [GtkChild]
    unowned Gtk.ScrolledWindow scrolled;

    public imageview (string name, string path) {
        // Object(
        //     title:name
        // );
        //
        this.name = name;
        this.path = path;

        this.title=name;

        //画像読み
        try {
            var pixbuf = new Gdk.Pixbuf.from_file (path);
            original_width = pixbuf.get_width ();
            original_height = pixbuf.get_height ();

            var texture = Gdk.Texture.for_pixbuf (pixbuf);
            picture.set_paintable (texture);

            // ズームの基準は「元のピクセルサイズ」
            zoom = 1.0;

        } catch (Error e) {
            win.show_error_toast (e.message);
        }

        this.map.connect (() => {
            if (initial_fit_done)
                return;
            if (original_width <= 0 || original_height <= 0)
                return;

            int avail_w = scrolled.get_width ();
            int avail_h = scrolled.get_height ();

            if (avail_w <= 0 || avail_h <= 0)
                return;

            fit_to_viewport (avail_w, avail_h);
            initial_fit_done = true;
        });

        // NavigationView に push されて画面に出る直前〜直後に呼ばれる
        this.shown.connect (() => {
            win = this.get_root() as Semboola.Window;
        });

        // ピンチジェスチャ
        var gesture_zoom = new Gtk.GestureZoom ();
        picture.add_controller (gesture_zoom);

        gesture_zoom.begin.connect ((sequence) => {
            gesture_base_zoom = zoom;
            last_scale = 1.0;

            // ピンチの中心を1回だけ記録
            double cx = 0.0;
            double cy = 0.0;
            gesture_zoom.get_bounding_box_center (out cx, out cy);

            // 取れなかったときの保険として Picture の中央も使う
            if (cx == 0.0 && cy == 0.0) {
                cx = picture.get_allocated_width ()  / 2.0;
                cy = picture.get_allocated_height () / 2.0;
            }

            gesture_center_x = cx;
            gesture_center_y = cy;
        });

        gesture_zoom.scale_changed.connect ((scale) => {
            if (original_width <= 0 || original_height <= 0)
                return;
            if (scale <= 0)
                return;

            // 今回のイベントでの相対倍率 delta
            double delta = scale / last_scale;
            last_scale = scale;

            // 1回のイベントで変わって良い倍率に上限をつける（±10%）
            const double MAX_STEP = 1.1;
            const double MIN_STEP = 1.0 / MAX_STEP;

            if (delta > MAX_STEP)
                delta = MAX_STEP;
            else if (delta < MIN_STEP)
                delta = MIN_STEP;

            double new_zoom = zoom * delta;
            new_zoom = new_zoom.clamp (0.05, 32.0);

            // ほとんど変化がないなら何もしない
            if (Math.fabs (new_zoom - zoom) < 0.005)
                return;

            var hadj = scrolled.get_hadjustment ();
            var vadj = scrolled.get_vadjustment ();

            double old_zoom = zoom;
            double content_w_before = original_width  * old_zoom;
            double content_h_before = original_height * old_zoom;

            double content_w_after  = original_width  * new_zoom;
            double content_h_after  = original_height * new_zoom;

            double cx = gesture_center_x;
            double cy = gesture_center_y;

            double old_x = hadj.value;
            double old_y = vadj.value;

            // 拡大前：画面上のどの位置を見ていたか（0.0〜1.0）
            double rel_x = 0.0;
            double rel_y = 0.0;

            if (content_w_before > 0)
                rel_x = (old_x + cx) / content_w_before;
            if (content_h_before > 0)
                rel_y = (old_y + cy) / content_h_before;

            // ズーム更新
            zoom = new_zoom;

            int new_w = (int) (original_width  * zoom);
            int new_h = (int) (original_height * zoom);

            picture.width_request  = new_w;
            picture.height_request = new_h;

            // 拡大後も同じ「相対位置」が指の下に来るようにスクロールを補正
            double new_x = rel_x * content_w_after - cx;
            double new_y = rel_y * content_h_after - cy;

            double max_x = hadj.upper - hadj.page_size;
            double max_y = vadj.upper - vadj.page_size;

            if (max_x < 0) max_x = 0;
            if (max_y < 0) max_y = 0;

            new_x = new_x.clamp (hadj.lower, max_x);
            new_y = new_y.clamp (vadj.lower, max_y);

            hadj.value = new_x;
            vadj.value = new_y;
        });

        gesture_zoom.end.connect ((sequence) => {
            last_scale = 1.0;
        });

    }

    static construct {
    }

    private void fit_to_viewport (int avail_w, int avail_h) {
        if (avail_w <= 0 || avail_h <= 0)
            return;

        // ビューポートに収まるような倍率を計算
        double scale_w = (double) avail_w / (double) original_width;
        double scale_h = (double) avail_h / (double) original_height;

        // 縦横どちらかキツい方に合わせる
        zoom = Math.fmin (scale_w, scale_h);

        apply_zoom ();
    }

    private void apply_zoom () {
        if (original_width <= 0 || original_height <= 0)
            return;

        int w = (int) Math.round (original_width * zoom);
        int h = (int) Math.round (original_height * zoom);

        // Picture を「このサイズの画像」として扱わせる
        // ScrolledWindow がはみ出しをスクロールしてくれる
        picture.width_request = w;
        picture.height_request = h;

        // ズームモードでは fit させたくないので NONE にしておくと分かりやすい
        picture.content_fit = Gtk.ContentFit.CONTAIN;
    }

    private string get_default_filename_from_url (string url) {
        var s = url;

        // ? と # はクエリ・フラグメントなので落とす
        var q = s.index_of_char ('?');
        if (q >= 0)
            s = s.substring (0, q);

        var hash = s.index_of_char ('#');
        if (hash >= 0)
            s = s.substring (0, hash);

        // 最後の / より後ろを取る
        var slash = s.last_index_of ("/");
        string name;
        if (slash >= 0 && slash + 1 < s.length) {
            name = s.substring (slash + 1);
        } else {
            name = s;
        }

        // 何も残らなかったとき
        if (name.strip ().length == 0) {
            name = "image";
        }

        return name;
    }

    private async void save () {
        // image_url と image_path はコンストラクタで受け取って保持している想定
        var default_name = get_default_filename_from_url (name);

        var dialog = new Gtk.FileDialog ();
        dialog.initial_name = default_name;

        try {
            // ユーザーが保存先を決めるまで待つ
            var file = yield dialog.save (win, null);
            if (file == null) {
                return; // キャンセル
            }

            var src = File.new_for_path (path);

            src.copy (file, FileCopyFlags.OVERWRITE, null, null);

        } catch (Error e) {
            win.show_error_toast (e.message);
        }
    }

    [GtkCallback]
    private void on_download_click () {
        save.begin ();
    }
}

/* ress.vala
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
using Gdk;
using Adw;
using FiveCh;

[GtkTemplate (ui = "/jp/lv34/Semboola/ress.ui")]
public class RessView : Adw.NavigationPage {

    private string url;
    private string name;
    private int read; // 既読行

    Semboola.Window win;

    private DatLoader loader;

    private GLib.ListStore store = new GLib.ListStore (typeof (ResRow.ResItem));
    private Gee.ArrayList<ResRow.ResItem> posts;

    // from: レス i が、どのレスにアンカーしているか   (i -> targets)
    private Gee.ArrayList<Gee.ArrayList<uint>> reply_to;

    // to:   レス i が、どのレスからアンカーされているか (sources -> i)
    private Gee.ArrayList<Gee.ArrayList<uint>> replied_from;

    // ID このIDが何レスしているか
    private class IdStats : Object {
        public string id   { get; construct; }
        public uint   nth  { get; construct; } // このIDの何番目のレスか
        public uint   total{ get; construct; } // このIDが全部で何レスか

        public IdStats (string id, uint nth, uint total) {
            Object (id: id, nth: nth, total: total);
        }
    }
    // ID -> そのIDのレスindex一覧（1-based ResItem.index）
    private Gee.HashMap<string,Gee.ArrayList<uint>> id_to_indices;

    // index(1-based) -> そのレスの x/x 情報
    private Gee.HashMap<uint,IdStats> index_to_id_stats;

    // 初期化フラグ
    private bool initialized = false;

    // ここまでロード
    private int res_count = 0;

    // スクロールいち
    private double saved_vadjustment = 0.0;

    [GtkChild]
    unowned Gtk.ListBox listview;

    public RessView (string url, string name, int read) {
        // Object(
        //     title:name
        // );
        //
        this.url = url;
        this.name = name;
        this.read = read;

        loader = new DatLoader ();

        // マウスクリック
        var click = new Gtk.GestureClick ();
        click.set_button (0);
        click.released.connect ((n_press, x, y) => {

            // spanと競合しないよう
            if (suppress_row_click_once)
                return;

            // LongPress 後の「離した左クリック」は1回だけ無視する
            if (suppress_after_long) {
                suppress_after_long = false;
                return;
            }

            // どのボタンか
            uint button = click.get_current_button ();

            // y は listview のローカル座標
            var row = listview.get_row_at_y ((int) y);
            if (row == null)
                return;

            int idx = row.get_index ();  // 0-based
            if (idx < 0 || idx >= posts.size)
                return;

            var post = posts[idx];

            switch (button) {
            case Gdk.BUTTON_PRIMARY:
                // 左クリック
                on_row_left_clicked (post, idx, n_press);
                break;
            case Gdk.BUTTON_SECONDARY:
                // 右クリック
                on_row_right_clicked (post, idx, x, y);
                break;
            default:
                // 中ボタンなど必要ならここに
                break;
            }
        });

        listview.add_controller (click);

        // タッチで右クリックエミュレーション
        var longp = new Gtk.GestureLongPress ();
        // タッチ専用にしておくとマウスの長押しには反応しない
        longp.set_touch_only (true);

        longp.pressed.connect ((x, y) => {
            if (suppress_row_click_once)
                return;

            var row = listview.get_row_at_y ((int) y);
            if (row == null)
                return;

            int idx = row.get_index ();
            if (idx < 0 || idx >= posts.size)
                return;

            var post = posts[idx];

            suppress_after_long = true;

            // 「タッチ長押し＝右クリック」と見なして同じハンドラへ
            on_row_right_clicked (post, idx, x, y);
        });

        listview.add_controller (longp);

        // NavigationView に push されて画面に出る直前〜直後に呼ばれる
        this.shown.connect (() => {
            win = this.get_root() as Semboola.Window;
            init_load.begin ();
        });

    }

    static construct {
        typeof (ResRow).ensure ();

        // 行がアクティブ化されたとき（pos は行番号）
        // listview.activate.connect (on_row_activated);
    }

    // ヘッダをクリック
    private void on_header_clicked (ResRow.ResItem post, int row_index, int n_press) {
        print (post.id);
        if (post.id == null || post.id == "")
            return;
        open_id_page(post.id);
    }

    // 左クリック
    private void on_row_left_clicked (ResRow.ResItem post, int row_index, int n_press) {
        if (n_press >= 2) {

            win.show_error_toast ("test- dc");
        } else {
            open_reply_tree_page (post.index);
        }
    }

    // 右クリック
    private void on_row_right_clicked (ResRow.ResItem post, int row_index, double x, double y) {
        win.show_error_toast ("test- r");
    }

    private void set_post_widgets (ResRow.ResItem post, Gtk.Label header, ClickableLabel body) {
        string safe_name = Markup.escape_text (post.name);
        string safe_date = Markup.escape_text (post.date);
        string id_part = (post.id != "")
            ? @" <span foreground='#c03030'>ID:$(Markup.escape_text (post.id))</span>"
            : "";

        IdStats? stats = null;
        if (index_to_id_stats != null && index_to_id_stats.has_key (post.index)) {
            stats = index_to_id_stats[post.index];
        }

        uint anchor_count = 0;
        string anchor_count_str = "";
        if (replied_from != null && post.index < replied_from.size) {
            anchor_count = (uint) replied_from[(int) post.index].size;
            if (anchor_count > 0)
                anchor_count_str = "(" + anchor_count.to_string () + ")";
        }

        if (stats == null || stats.total < 2) {
            header.set_markup (@"<b>$(post.index)</b><span foreground='#FF5555'>$(anchor_count_str)</span> $(post.name) $safe_date$id_part");
        } else {
            header.set_markup (@"<b>$(post.index)</b><span foreground='#FF5555'>$(anchor_count_str)</span> $(post.name) $safe_date$id_part ($(stats.nth)/$(stats.total))");
        }

        var spans = post.get_spans ();
        body.set_spans (spans);
    }

    // 最初の読み込み
    private async void init_load () {
        if (initialized) {
            return;
        }

        yield reload();

        initialized = true;
    }

    private void refresh_existing_rows_incremental (int existing_count) {
        int i = 0;

        Idle.add (() => {
            int chunk = 30;

            for (int n = 0; n < chunk && i < existing_count; n++, i++) {
                var post = posts[i];

                var row = listview.get_row_at_index (i);
                if (row == null)
                    continue;

                var box = row.get_child () as Gtk.Box;
                if (box == null)
                    continue;

                // 生成時: header が先、body が次に append している前提
                Gtk.Widget? child = box.get_first_child ();
                var header = child as Gtk.Label;

                ClickableLabel? body = null;
                if (child != null)
                    body = child.get_next_sibling () as ClickableLabel;

                if (header != null && body != null) {
                    set_post_widgets (post, header, body);
                    // span の signal は生成時に1回だけ繋いでいるので、そのまま使える
                }
            }

            return i < existing_count;
        });
    }

    // 全構築用（初回やフルリロード用）
    // 旧 clear & rebuild とほぼ同じ
    private void rebuild_listbox_incremental_full () {
        clear_listbox ();

        int i = 0;
        Idle.add (() => {
            int chunk = 10;
            for (int n = 0; n < chunk && i < posts.size; n++, i++) {
                append_row_for_post (posts[i]);
            }
            res_count = i;
            return i < posts.size;
        });
    }

    // 追加レスだけ作る用
    private void rebuild_listbox_incremental_append_only () {
        int i = res_count;
        Idle.add (() => {
            int chunk = 10;
            for (int n = 0; n < chunk && i < posts.size; n++, i++) {
                append_row_for_post (posts[i]);
            }
            res_count = i;
            return i < posts.size;
        });
    }

    // 共通の row 生成ヘルパ
    private void append_row_for_post (ResRow.ResItem post) {

        var row_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
        row_box.margin_top = 6;
        row_box.margin_bottom = 6;
        row_box.margin_start = 8;
        row_box.margin_end = 16;

        var header = new Gtk.Label (null);
        header.use_markup = true;
        header.xalign = 0.0f;
        header.wrap = true;
        header.wrap_mode = Pango.WrapMode.WORD_CHAR;

        var body = new ClickableLabel ();

        set_post_widgets (post, header, body);

        var header_click = new Gtk.GestureClick ();
        header_click.set_button (0);

        header_click.released.connect ((n_press, x, y) => {
            consume_row_click_once ();

            var row = header.get_ancestor (typeof (Gtk.ListBoxRow)) as Gtk.ListBoxRow;
            if (row == null)
                return;

            int idx = row.get_index ();
            if (idx < 0 || idx >= posts.size)
                return;

            var p = posts[idx];

            on_header_clicked (p, idx, n_press);
        });

        header.add_controller (header_click);

        body.span_left_clicked.connect ((span) => {
            on_span_left_clicked (post, span);
        });
        body.span_right_clicked.connect ((span, x, y) => {
            on_span_right_clicked (post, span, x, y, body);
        });

        row_box.append (header);
        row_box.append (body);

        var row = new Gtk.ListBoxRow ();
        row.set_child (row_box);

        listview.append (row);
    }



    private void clear_listbox () {
        Gtk.Widget? child = listview.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            listview.remove (child);
            child = next;
        }
    }


    private int last_post_count = 0;
    private async void reload () {

        this.title=_("Loading...");

        //save_scroll_position ();

        try {
            var cancellable = new Cancellable ();
            var new_posts = yield loader.load_from_url_async (url, cancellable);

            int old_count = (posts != null) ? posts.size : 0;
            int new_count = new_posts.size;

            // モデル差し替え
            posts = new_posts;

            // アンカー索引
            build_anchor_index ();

            // ID索引
            build_id_index ();


            if (old_count == 0) {
                // 初回
                res_count = 0;
                rebuild_listbox_incremental_full ();
            } else if (new_count < old_count) {
                // スレが短くなった
                clear_listbox ();
                res_count = 0;
                rebuild_listbox_incremental_full ();
            } else {
                // 1) 既存の行のヘッダ／本文だけ更新
                refresh_existing_rows_incremental (old_count);

                // 2) 新しく増えた分だけ row を追加
                res_count = old_count;
                rebuild_listbox_incremental_append_only ();
            }

            last_post_count = new_count;

            // DB更新 何件読んだかで未読がわかる
            try {
                string? board_key = FiveCh.Board.guess_board_key_from_url (url);
                string? site_base = FiveCh.Board.guess_site_base_from_url (url);
                string? threadkey = FiveCh.DatLoader.guess_threadkey_from_url (url);


                Db.DB db = new Db.DB();
                Sqlite.Statement st;
                string sql = """
                    INSERT INTO threadlist (board_url, bbs_id, thread_id, current_res_count, favorite, last_touch_date, title)
                    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                    ON CONFLICT(board_url, bbs_id, thread_id) DO UPDATE SET
                    title = excluded.title,
                    current_res_count = excluded.current_res_count,
                    last_touch_date = excluded.last_touch_date
                """;
                int rc = db.db.prepare_v2 (sql, -1, out st, null);

                if (rc != Sqlite.OK) {
	                stderr.printf ("Error: %d: %s\n", db.db.errcode (), db.db.errmsg ());
	                return;
                }

                st.bind_text (1, site_base);
                st.bind_text (2, board_key);
                st.bind_text (3, threadkey);
                st.bind_int  (4, posts.size);
                st.bind_int  (5, 0);
                st.bind_int64 (6, new DateTime.now_utc ().to_unix ());
                st.bind_text (7, name);

                rc = st.step ();
                st.reset ();
                if (rc != Sqlite.DONE) {
                    stderr.printf ("Error: %d: %s\n", db.db.errcode (), db.db.errmsg ());
                    win.show_error_toast (_("Database error"));
                }

            } catch {
                win.show_error_toast (_("Database error"));
            }
        } catch (Error e) {
            win.show_error_toast (_("Invalid error"));
        } finally {
             this.title=name;
        }
    }

    // spanとlist全体のクリックが競合するのを防ぐ
    private bool suppress_row_click_once = false;
    private void consume_row_click_once () {
        suppress_row_click_once = true;
        // 次のIdleで自動的に解除
        Idle.add (() => {
            suppress_row_click_once = false;
            return false;
        });
    }

    // 長押しと左クリックが競合するのを防ぐ
    private bool suppress_after_long = false;

    // -------- Spanクリック時の動作 --------

    private void on_span_left_clicked (ResRow.ResItem post, Span span) {

        switch (span.type) {
        case SpanType.REPLY:
            if (span.payload != null) {
                uint target;
                try {
                    target = (uint) int.parse (span.payload);
                } catch (Error e) {
                    return;
                }
                scroll_to_post (target);
            }
            break;
        case SpanType.URL:
            if (span.payload != null) {
                try {
                    var launcher = new Gtk.UriLauncher (span.payload);
                    launcher.launch.begin (null, null);
                } catch (Error e) {
                    // 失敗時は無視
                }
            }
            break;
        case SpanType.ID:
            if (span.payload != null) {
                var target = span.payload.substring (3, -1);
                open_id_page(target);
            }
            break;
        default:
            return;
        }
        consume_row_click_once ();
    }

    private void on_span_right_clicked (ResRow.ResItem post, Span span, double x, double y, Gtk.Widget widget) {
        consume_row_click_once ();

        switch (span.type) {
        case SpanType.REPLY:
            if (span.payload != null) {
                try {

                } catch (Error e) {}
            }
            break;
        case SpanType.URL:
            if (span.payload != null) {
                try {

                } catch (Error e) {}
            }
            break;
        default:
            break;
        }
    }

    // アンカー一覧を保持
    private void build_anchor_index () {
        int n = posts.size;

        reply_to = new Gee.ArrayList<Gee.ArrayList<uint>> ();
        replied_from = new Gee.ArrayList<Gee.ArrayList<uint>> ();

        // 0番ダミー
        reply_to.add (new Gee.ArrayList<uint> ());
        replied_from.add (new Gee.ArrayList<uint> ());

        for (int i = 1; i <= n; ++i) {
            reply_to.add (new Gee.ArrayList<uint> ());
            replied_from.add (new Gee.ArrayList<uint> ());
        }

        const int MAX_PER_POST = 10;

        for (int i = 0; i < n; ++i) {
            var post = posts[i];
            uint from_index = post.index; // 1-based の想定
            if (from_index < 1 || from_index > n)
                continue;

            int budget = MAX_PER_POST;

            var spans = post.get_spans ();

            foreach (var span in spans) {
                if (budget <= 0)
                    break;  // 10レス超え

                if (span.type != SpanType.REPLY || span.payload == null)
                    continue;

                // この span からは "budget" 件まで取り出す
                var targets = parse_reply_payload (span.payload, n, budget);

                foreach (uint t in targets) {
                    reply_to[(int)from_index].add (t);
                    replied_from[(int)t].add (from_index);
                }

                budget -= targets.size;
            }
        }
    }


    // span から複数アンカー番号を取る
    // max_targets: この span から何個まで追加してよいか（残り枠）
    private Gee.ArrayList<uint> parse_reply_payload (string payload,
                                                     int max_index,
                                                     int max_targets) {
        var list = new Gee.ArrayList<uint> ();

        if (payload == null || payload.length == 0 || max_targets <= 0)
            return list;

        string s = payload;

        if (s.has_prefix (">>"))
            s = s.substring (2); // "1-3,5"

        foreach (var part0 in s.split (",")) {
            if (list.size >= max_targets)
                break;

            string part = part0.strip ();
            if (part.length == 0)
                continue;

            int dash = part.index_of ("-");
            if (dash < 0) {
                // 単発: "5"
                try {
                    int n = int.parse (part);
                    if (n >= 1 && n <= max_index) {
                        list.add ((uint) n);
                        if (list.size >= max_targets)
                            break;
                    }
                } catch (Error e) {}
            } else {
                // 範囲: "1-3"
                string a = part.substring (0, dash).strip ();
                string b = part.substring (dash + 1).strip ();
                try {
                    int start = int.parse (a);
                    int end   = int.parse (b);
                    if (end < start) {
                        int tmp = start;
                        start = end;
                        end = tmp;
                    }

                    for (int i = start; i <= end; i++) {
                        if (i < 1 || i > max_index)
                            continue;

                        list.add ((uint) i);
                        if (list.size >= max_targets)
                            break;
                    }
                } catch (Error e) {}
            }
        }

        return list;
    }

    // IDごとの索引を撮る
    private void build_id_index () {
        id_to_indices = new Gee.HashMap<string,Gee.ArrayList<uint>> (
            (Gee.HashDataFunc<string>) GLib.str_hash,
            (Gee.EqualDataFunc<string>) GLib.str_equal
        );
        index_to_id_stats = new Gee.HashMap<uint,IdStats> ();

        int n = posts.size;
        for (int i = 0; i < n; i++) {
            var post = posts[i];
            string id = post.id;

            if (id == null || id == "")
                continue; // IDなしはスキップ

            Gee.ArrayList<uint>? list;
            if (id_to_indices.has_key (id)) {
                list = id_to_indices[id];
            } else {
                list = new Gee.ArrayList<uint> ();
                id_to_indices[id] = list;
            }

            list.add (post.index);  // ResItem.index は 1-based の想定
        }

        // index -> (nth, total) を埋める
        foreach (string id in id_to_indices.keys) {
            var list = id_to_indices[id];
            uint total = (uint) list.size;

            for (int i = 0; i < list.size; i++) {
                uint idx = list[i];
                uint nth = (uint) (i + 1);

                index_to_id_stats[idx] = new IdStats (id, nth, total);
            }
        }
    }


    private void scroll_to_post (uint index) {
        var row = listview.get_row_at_index ((int) index-1);
        if (row == null) {
            return;
        }

        // row の左上の座標を listbox 基準で取得
        double rx, ry;
        row.translate_coordinates (listview, 0, 0, out rx, out ry);

        // 親チェーンから ScrolledWindow を取る
        // ScrolledWindow -> Viewport -> ListBox という構造前提
        var parent = listview.get_parent();
        Gtk.ScrolledWindow? scrolled = null;

        while (parent != null) {
            scrolled = parent as Gtk.ScrolledWindow;
            if (scrolled != null)
                break;
            parent = parent.get_parent();
        }

        if (scrolled == null)
            return;

        var vadj = scrolled.vadjustment;

        double vle = (double) ry;

        // スクロール範囲にクランプ
        if (vle < vadj.lower)
            vle = vadj.lower;
        if (vle > vadj.upper - vadj.page_size)
            vle = vadj.upper - vadj.page_size;

        Idle.add (() => {
            vadj.value = vle;
            return false; // 一回だけ
        });

    }

    private void open_id_page (string id) {
        // ツリー用 ListBox を作成
        var id_list = create_id_listbox (id);

        if (id_list == null)
            return;

        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        nav.push(new replies (name, id_list));
    }

    public Gtk.ListBox create_id_listbox (string id) {

        var id_list = new Gtk.ListBox ();
        id_list.show_separators = true;
        id_list.selection_mode = Gtk.SelectionMode.NONE;

        var idxs = id_to_indices[id];
        foreach (var idx in idxs) {
            var p = posts[(int) idx-1];
            var row = create_reply_row (p);
            id_list.append (row);
        }
        return id_list;
    }

    private void open_reply_tree_page (uint root_index) {
        // ツリー用 ListBox を作成
        var tree_list = create_reply_tree_listbox (root_index);

        if (tree_list == null)
            return;

        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        nav.push(new replies (name, tree_list));
    }

    public Gtk.ListBox create_reply_tree_listbox (uint start_idx) {
        uint root = find_conversation_root (start_idx);

        Gee.ArrayList<uint> order;
        Gee.ArrayList<int> depths;
        Gee.HashMap<uint,uint> parent;

        build_reply_tree_indices (root, out order, out depths, out parent);

        var tree_list = new Gtk.ListBox ();
        tree_list.show_separators = true;
        tree_list.selection_mode = Gtk.SelectionMode.NONE;

        if (order.size == 1)
            return null;

        for (int i = 0; i < order.size; i++) {
            uint idx = order[i];
            int depth = depths[i];

            // posts は 0-based, index は 1-based
            var post = posts[(int) idx - 1];

            var row = create_reply_row (post);

            tree_list.append (row);
        }

        return tree_list;
    }

    // start_index から上方向に辿っていって、会話のrootを決める
    private uint find_conversation_root (uint start_index) {
        int n = posts.size;
        if (n == 0)
            return start_index;

        // 1..n 用 visited でループ対策
        bool[] visited = new bool[n + 1];

        uint current = start_index;

        while (true) {
            if (current < 1 || current > (uint) n)
                break;

            int ci = (int) current;
            if (visited[ci])
                break;
            visited[ci] = true;

            if (ci >= reply_to.size)
                break;

            var parents = reply_to[ci];
            if (parents == null || parents.size == 0)
                break;

            // 複数アンカーの場合は「いちばん古そうな親」 (= 最小 index) を採用
            uint next = parents[0];
            foreach (uint p in parents) {
                if (p < next)
                    next = p;
            }

            current = next;
        }

        return current;
    }


    // 指定した root からアンカーのぶんだけツリー順に index を並べる
    // order: 表示順の index 配列
    // depths: 各 index の深さ (0 = root)
    // parent: child -> parent のマップ（root は登録されない）
    public void build_reply_tree_indices (uint root_index,
                                          out Gee.ArrayList<uint> order,
                                          out Gee.ArrayList<int> depths,
                                          out Gee.HashMap<uint,uint> parent) {
        order = new Gee.ArrayList<uint> ();
        depths = new Gee.ArrayList<int> ();
        parent = new Gee.HashMap<uint,uint> ();

        int n = posts.size;
        if (n == 0)
            return;

        if (root_index < 1 || root_index > (uint) n)
            return;

        // 1〜n 用の visited 配列
        bool[] visited = new bool[n + 1];

        dfs_build_tree (root_index, 0, visited, order, depths, parent);
    }

    private void dfs_build_tree (uint idx,
                                 int depth,
                                 bool[] visited,
                                 Gee.ArrayList<uint> order,
                                 Gee.ArrayList<int> depths,
                                 Gee.HashMap<uint,uint> parent) {
        if (idx >= (uint) visited.length)
            return;

        if (visited[idx])
            return;
        visited[idx] = true;

        // 自分を追加
        order.add (idx);
        depths.add (depth);

        // このレスにアンカーしているレスたち（= 子ノード）
        if (idx >= (uint) replied_from.size)
            return;

        var children = replied_from[(int) idx]; // Gee.ArrayList<uint>

        foreach (uint child in children) {
            // すでにどこかの経路で出てきたレスはスキップ
            // if (visited[child])
            //     continue;

            // ツリー上での親を記録
            parent[child] = idx;

            dfs_build_tree (child, depth + 1, visited, order, depths, parent);
        }
    }

    private Gtk.ListBoxRow create_reply_row (ResRow.ResItem post) {
        var row_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
        row_box.margin_top = 6;
        row_box.margin_bottom = 6;

        //int indent_px = 0 * depth;  // しない
        row_box.margin_start = 8;
        row_box.margin_end = 16;

        var header = new Gtk.Label (null);
        header.use_markup = true;
        header.xalign = 0.0f;
        header.wrap = true;
        header.wrap_mode = Pango.WrapMode.WORD_CHAR;

        var body = new ClickableLabel ();

        // 普段と同じ見出し・本文生成
        set_post_widgets (post, header, body);

        row_box.append (header);
        row_box.append (body);

        var row = new Gtk.ListBoxRow ();
        row.set_child (row_box);
        return row;
    }

    [GtkCallback]
    private void on_add_click () {
        var window = this.get_ancestor (typeof (Gtk.Window)) as Gtk.Window;
        var popup = new new_res (window, g_app, url);
        popup.submitted.connect (() => {
            // 終わったら再読み込み
            this.reload.begin ();
        });
        popup.present ();
    }

    [GtkCallback]
    private void on_reload_click () {
        reload.begin ();
    }
}

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
using Soup;

[GtkTemplate (ui = "/jp/lv34/Semboola/ress.ui")]
public class RessView : Adw.NavigationPage {

    private string url;
    private string name;
    private int read; // 既読行
    private bool is_read = false;

    Semboola.Window win;

    private DatLoader loader;

    private ImageControl imgcon = new ImageControl ();

    // private GLib.ListStore store = new GLib.ListStore (typeof (ResRow.ResItem));
    private Gee.ArrayList<ResRow.ResItem> posts;

    // from: レス i が、どのレスにアンカーしているか   (i -> targets)
    private Gee.ArrayList<Gee.ArrayList<uint>> reply_to;

    // to:   レス i が、どのレスからアンカーされているか (sources -> i)
    private Gee.ArrayList<Gee.ArrayList<uint>> replied_from;

    // ID このIDが何レスしているか
    private class IdStats : Object {
        public string id   { get; construct; }
        public uint nth  { get; construct; } // このIDの何番目のレスか
        public uint total { get; construct; } // このIDが全部で何レスか

        public IdStats (string id, uint nth, uint total) {
            Object (id: id, nth: nth, total: total);
        }
    }
    // ID -> そのIDのレスindex一覧（1-based ResItem.index）
    private Gee.HashMap<string, Gee.ArrayList<uint>> id_to_indices;

    // index(1-based) -> そのレスの x/x 情報
    private Gee.HashMap<uint, IdStats> index_to_id_stats;

    // 初期化フラグ
    private bool initialized = false;

    // ここまでロード
    private int res_count = 0;

    // 直近で右クリックした行のindex
    private uint right_clicked_row = 1;
    // クリックが行われたとき、画面に映っているインデックスの並び(1スタート)
    private Gee.ArrayList<uint> clicked_indexes = new Gee.ArrayList<uint> ();

    // repliesのインスタンス
    private replies replies_view;
    // repliesがどのモードで開いているか
    private replies.Type rep_type = replies.Type.NONE;
    // repliesのroot_index
    private uint rep_root_index = 0;
    private string rep_id = "";

    [GtkChild]
    unowned Gtk.ListBox listview;

    [GtkChild]
    unowned Gtk.ScrolledWindow scr_window;

    [GtkChild]
    unowned Gtk.PopoverMenu context_popover;

    [GtkChild]
    unowned Gtk.ToggleButton button_search;

    [GtkChild]
    unowned Gtk.SearchBar bar_search;

    [GtkChild]
    unowned Gtk.SearchEntry entry_search;

    private SimpleActionGroup page_actions;

    public RessView (string url, string name, int read) {

        this.url = url;
        this.name = name;
        this.read = read;

        button_search.bind_property (
            "active",
            bar_search, "search-mode-enabled",
            BindingFlags.BIDIRECTIONAL
        );

        loader = new DatLoader ();

        setup_listbox_clicks (listview);

        // NavigationView に push されて画面に出る直前〜直後に呼ばれる
        this.shown.connect (() => {
            win = this.get_root () as Semboola.Window;
            clicked_indexes.clear (); // 並び=通常
            rep_type = replies.Type.NONE;
            init_load.begin ();
        });
    }

    construct {
        page_actions = new SimpleActionGroup ();

        var top_action = new SimpleAction ("thread_top", null);
        top_action.activate.connect ((param) => {
            on_top_activate ();
        });
        page_actions.add_action (top_action);

        var copy_action = new SimpleAction ("copy", VariantType.STRING);
        copy_action.activate.connect ((param) => {
            on_copy_activate (param);
        });
        page_actions.add_action (copy_action);

        // reply アクション
        var reply_action = new SimpleAction ("reply", null);
        reply_action.activate.connect ((param) => {
            on_reply_activate ();
        });
        page_actions.add_action (reply_action);

        // mark アクション
        var mark_action = new SimpleAction ("mark", null);
        mark_action.activate.connect ((param) => {
            on_mark_activate.begin ();
        });
        page_actions.add_action (mark_action);

        // "win." プレフィックスでこのページに登録
        this.insert_action_group ("win", page_actions);
    }

    static construct {
        typeof (ResRow).ensure ();

        // 行がアクティブ化されたとき（pos は行番号）
        // listview.activate.connect (on_row_activated);
    }

    // Listboxクリック初期化
    private void setup_listbox_clicks (Gtk.ListBox box) {
        var click = new Gtk.GestureClick ();
        click.set_button (0);

        click.released.connect ((n_press, x, y) => {
            if (suppress_row_click_once)
                return;
            if (suppress_after_long) {
                suppress_after_long = false;
                return;
            }

            uint button = click.get_current_button ();

            var row = box.get_row_at_y ((int) y);
            if (row == null)
                return;

            int idx = row.get_index ();
            if (idx < 0 || idx >= posts.size)
                return;

            if (clicked_indexes.is_empty) {
                // idx = idx;
            } else {
                idx = (int) clicked_indexes[idx]-1;
            }


            var post = posts[idx];

            switch (button) {
                case Gdk.BUTTON_PRIMARY:
                    on_row_left_clicked (post, idx, n_press);
                    break;
                case Gdk.BUTTON_SECONDARY:
                    on_row_right_clicked (click.widget as Gtk.ListBox, row, post, idx, x, y);
                    break;
            }
        });

        box.add_controller (click);

        // LongPressも同様に box に対して付ける
        var longp = new Gtk.GestureLongPress ();
        longp.set_touch_only (true);

        longp.pressed.connect ((x, y) => {
            if (suppress_row_click_once)
                return;

            var row = box.get_row_at_y ((int) y);
            if (row == null)
                return;

            int idx = row.get_index ();
            if (idx < 0 || idx >= posts.size)
                return;

            if (clicked_indexes.is_empty) {
                // idx = idx;
            } else {
                idx = (int) clicked_indexes[idx]-1;
            }

            var post = posts[idx];

            suppress_after_long = true;
            on_row_right_clicked (longp.widget as Gtk.ListBox, row, post, idx, x, y);
        });

        box.add_controller (longp);
    }

    // ヘッダをクリック
    private void on_header_clicked (ResRow.ResItem post, int row_index, int n_press) {
        if (post.id == null || post.id == "")
            return;
        open_id_page (post.id);
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
    private void on_row_right_clicked (Gtk.ListBox listbox, ListBoxRow row, ResRow.ResItem post, int row_index, double x, double y) {
        right_clicked_row = post.index;
        show_context_menu_for_row (listbox, row, x, y);
    }

    private void show_context_menu_for_row (Gtk.ListBox listbox, ListBoxRow row, double x, double y) {
        // Popover の親は ScrolledWindow に統一安倍晋三
        var pop = context_popover;

        // listview 座標 -> scr_window 座標 に変換
        Graphene.Point src = Graphene.Point (); // Graphene.Point
        src.init ((float) x, (float) y);
        Graphene.Point dest;

        // listview 座標 -> scr_window 座標 に変換
        if (!listbox.compute_point (win, src, out dest)) {
            return;
        }

        Gdk.Rectangle rect = {
            (int) dest.x,
            (int) dest.y,
            1,
            1
        };

        // 親はスクロールウィンドウに固定
        pop.set_parent (this);
        pop.set_pointing_to (rect);

        pop.popup ();
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

        yield reload ();

        initialized = true;
    }

    private void refresh_mark (ResRow.ResItem post, Gtk.ListBoxRow row) {
        // 書き込みマーク
        switch (post.mark) {
        case post.MarkType.MINE :
            row.remove_css_class ("row-reply");
            row.add_css_class ("row-mine");
            break;
        case post.MarkType.REPLY :
            row.remove_css_class ("row-mine");
            row.add_css_class ("row-reply");
            break;
        default:
            row.remove_css_class ("row-reply");
            row.remove_css_class ("row-mine");
            break;
        }
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
                Gtk.Widget ? child = box.get_first_child ();
                var header = child as Gtk.Label;

                ClickableLabel? body = null;
                if (child != null)
                    body = child.get_next_sibling () as ClickableLabel;

                if (header != null && body != null) {
                    set_post_widgets (post, header, body);
                    // span の signal は生成時に1回だけ繋いでいるので、そのまま使える
                }

                refresh_mark(post, row);
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
            int chunk = 30;
            for (int n = 0; n < chunk && i < posts.size; n++, i++) {
                append_row_for_post.begin (posts[i]);
            }
            res_count = i;
            return i < posts.size;
        });
    }

    // 追加レスだけ作る用
    private void rebuild_listbox_incremental_append_only () {
        int i = res_count;
        Idle.add (() => {
            int chunk = 30;
            for (int n = 0; n < chunk && i < posts.size; n++, i++) {
                append_row_for_post.begin (posts[i]);
            }
            res_count = i;
            return i < posts.size;
        });
    }

    private async void append_row_for_post (ResRow.ResItem post) {
        var row = build_row_for_post (post);
        refresh_mark(post, row);
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
    private int old_count;
    private async void reload (bool disponly=false) {

        this.title = _("Loading...");

        // save_scroll_position ();

        try {
            var cancellable = new Cancellable ();
            Gee.ArrayList<ResRow.ResItem> new_posts;
            if (disponly)//表示だけリロードしたいときがある
                new_posts = posts;
            else
                new_posts = yield loader.load_from_url_async (url, cancellable);

            name = loader.get_title ();

            old_count = (posts != null) ? posts.size : 0;
            int new_count = new_posts.size;

            // モデル差し替え
            posts = new_posts;

            // アンカー索引
            build_anchor_index ();

            // ID索引
            build_id_index ();

            // 自分の書き込みを検索してインデックスを振る+振られたものを保持+リプライも見る
            mark_posthist ();

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


                Db.DB db = new Db.DB ();
                string sql = """
                    INSERT INTO threadlist (board_url, bbs_id, thread_id, current_res_count, favorite, last_touch_date, title)
                    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                    ON CONFLICT(board_url, bbs_id, thread_id) DO UPDATE SET
                    title = excluded.title,
                    current_res_count = excluded.current_res_count,
                    last_touch_date = excluded.last_touch_date
                """;

                db.exec (sql, { site_base, board_key, threadkey, posts.size.to_string (), "0", new DateTime.now_utc ().to_unix ().to_string (), name });
            } catch (Error e) {
                win.show_error_toast (e.message);
            }
        } catch (Error e) {
            win.show_error_toast (e.message);
        } finally {
            this.title = name;
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
    private async void span_click (ResRow.ResItem post, Span span) {
        switch (span.type) {
        case SpanType.REPLY :
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
        case SpanType.ID :
            if (span.payload != null) {
                var target = span.payload.substring (3, -1);
                open_id_page (target);
            }
            break;
        case SpanType.URL :
        case SpanType.URL_BOARD :
        case SpanType.URL_THREAD :
            if (span.payload != null) {
                var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
                if (nav == null) {
                    return;
                }
                common.open_url (span.payload, nav);
            }
            break;
        default:
            return;
        }
    }

    private void on_span_left_clicked (ResRow.ResItem post, Span span) {
        if (span.type == SpanType.NORMAL) {
            return;
        }

        span_click.begin (post, span);
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
                    break; // 10レス超え

                if (span.type != SpanType.REPLY || span.payload == null)
                    continue;

                // この span からは "budget" 件まで取り出す
                var targets = parse_reply_payload (span.payload, n, budget);

                foreach (uint t in targets) {
                    reply_to[(int) from_index].add (t);
                    replied_from[(int) t].add (from_index);
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
                    int end = int.parse (b);
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
        id_to_indices = new Gee.HashMap<string, Gee.ArrayList<uint>> (
                                                                      (Gee.HashDataFunc<string>) GLib.str_hash,
                                                                      (Gee.EqualDataFunc<string>) GLib.str_equal
        );
        index_to_id_stats = new Gee.HashMap<uint, IdStats> ();

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

            list.add (post.index); // ResItem.index は 1-based の想定
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
        var row = listview.get_row_at_index ((int) index - 1);
        if (row == null) {
            return;
        }

        // 慣性スクロールを一時的に切る
        scr_window.kinetic_scrolling = false;

        // row の左上の座標を listbox 基準で取得
        double rx, ry;
        row.translate_coordinates (listview, 0, 0, out rx, out ry);

        // 親チェーンから ScrolledWindow を取る
        // ScrolledWindow -> Viewport -> ListBox という構造前提
        var parent = listview.get_parent ();
        Gtk.ScrolledWindow? scrolled = null;

        while (parent != null) {
            scrolled = parent as Gtk.ScrolledWindow;
            if (scrolled != null)
                break;
            parent = parent.get_parent ();
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
            scr_window.kinetic_scrolling = true;
            return false; // 一回だけ
        });
    }

    private void open_search_page (string target) {
        var pop = !clicked_indexes.is_empty;

        // ツリー用 ListBox を作成
        var search_list = create_search_listbox (target);

        if (search_list == null)
            return;

        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        if (pop) {
            nav.pop ();
        }

        replies_view = new replies (name, search_list);
        rep_type = replies.Type.SEARCH;
        nav.push (replies_view);
    }

    Gtk.ListBox search_list;
    public Gtk.ListBox create_search_listbox (string target) {
        clicked_indexes.clear ();

        search_list = new Gtk.ListBox ();
        search_list.show_separators = true;
        search_list.selection_mode = Gtk.SelectionMode.NONE;

        foreach (var p in posts) {
            if (!p.body.contains (target))
                continue;

            var row = build_row_for_post (p);
            search_list.append (row);

            // 並びを保存
            clicked_indexes.add (p.index);

            refresh_mark(p, row);
        }

        setup_listbox_clicks (search_list);
        return search_list;
    }

    private void open_id_page (string id) {
        var pop = !clicked_indexes.is_empty;
        rep_id = id;

        // ツリー用 ListBox を作成
        var id_list = create_id_listbox (id);

        if (id_list == null)
            return;

        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        if (pop) {
            nav.pop ();
        }

        replies_view = new replies (name, id_list);
        rep_type = replies.Type.ID;
        nav.push (replies_view);
    }

    Gtk.ListBox id_list;
    public Gtk.ListBox create_id_listbox (string id) {
        clicked_indexes.clear ();

        id_list = new Gtk.ListBox ();
        id_list.show_separators = true;
        id_list.selection_mode = Gtk.SelectionMode.NONE;

        var idxs = id_to_indices[id];
        foreach (var idx in idxs) {
            var p = posts[(int) idx - 1];
            var row = build_row_for_post (p);
            id_list.append (row);

            // 並びを保存
            clicked_indexes.add (idx);

            refresh_mark(p, row);
        }

        setup_listbox_clicks (id_list);
        return id_list;
    }

    private void open_reply_tree_page (uint root_index) {
        var pop = !clicked_indexes.is_empty;
        rep_root_index = root_index;

        // ツリー用 ListBox を作成
        var tree_list = create_reply_tree_listbox (root_index);

        if (tree_list == null)
            return;

        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        if (pop) {
            nav.pop ();
        }

        replies_view = new replies (name, tree_list);
        rep_type = replies.Type.REPLIES;
        nav.push (replies_view);
    }

    Gtk.ListBox tree_list;
    public Gtk.ListBox create_reply_tree_listbox (uint start_idx) {
        clicked_indexes.clear ();
        uint root = find_conversation_root (start_idx);

        Gee.ArrayList<uint> order;
        Gee.ArrayList<int> depths;
        Gee.HashMap<uint, uint> parent;

        build_reply_tree_indices (root, out order, out depths, out parent);

        tree_list = new Gtk.ListBox ();
        tree_list.show_separators = true;
        tree_list.selection_mode = Gtk.SelectionMode.NONE;

        if (order.size == 1)
            return null;

        for (int i = 0; i < order.size; i++) {
            uint idx = order[i];
            int depth = depths[i];

            // posts は 0-based, index は 1-based
            var post = posts[(int) idx - 1];

            var row = build_row_for_post (post);

            tree_list.append (row);

            // 並びを保存
            clicked_indexes.add (idx);

            refresh_mark(post, row);
        }

        setup_listbox_clicks (tree_list);

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
                                          out Gee.HashMap<uint, uint> parent) {
        order = new Gee.ArrayList<uint> ();
        depths = new Gee.ArrayList<int> ();
        parent = new Gee.HashMap<uint, uint> ();

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
                                 Gee.HashMap<uint, uint> parent) {
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
            // continue;

            // ツリー上での親を記録
            parent[child] = idx;

            dfs_build_tree (child, depth + 1, visited, order, depths, parent);
        }
    }

    private Gtk.ListBoxRow build_row_for_post (ResRow.ResItem post, int depth = 0) {
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
        header_click.set_button (1);

        header_click.released.connect ((n_press, x, y) => {
            consume_row_click_once ();

            var row = header.get_ancestor (typeof (Gtk.ListBoxRow)) as Gtk.ListBoxRow;
            if (row == null)
                return;

            int idx = row.get_index ();
            if (idx < 0 || idx >= posts.size)
                return;

            if (clicked_indexes.is_empty) {
                // idx = idx;
            } else {
                idx = (int) clicked_indexes[idx]-1;
            }

            var p = posts[idx];

            on_header_clicked (p, idx, n_press);
        });

        header.add_controller (header_click);

        body.span_left_clicked.connect ((span) => {
            on_span_left_clicked (post, span);
        });

        body.span_right_clicked.connect ((span, x, y) => {
            // on_span_right_clicked (post, span, x, y, body);
        });

        row_box.append (header);
        row_box.append (body);

        // 画像サムネイル''
        var image_urls = imgcon.find_image_urls_for_post (post);
        if (image_urls.size > 0) {
            var thumbs_box = new Gtk.FlowBox ();
            thumbs_box.orientation = Gtk.Orientation.HORIZONTAL;
            thumbs_box.selection_mode = Gtk.SelectionMode.NONE;
            thumbs_box.row_spacing = 4;
            thumbs_box.column_spacing = 4;
            thumbs_box.valign = Gtk.Align.START;
            thumbs_box.halign = Gtk.Align.START;
            thumbs_box.max_children_per_line = 3; // 1行あたりのサムネ数上限

            foreach (var url in image_urls) {
                var thumb = new Gtk.Picture ();
                thumb.content_fit = Gtk.ContentFit.CONTAIN;
                thumb.width_request = ImageControl.THUMB_WIDTH;
                thumb.height_request = ImageControl.THUMB_HEIGHT;
                thumb.can_shrink = false;

                // FlowBoxChild に包んで追加
                var child = new Gtk.FlowBoxChild ();
                child.set_child (thumb);
                thumbs_box.insert (child, -1);

                var click = new Gtk.GestureClick ();
                click.set_button (0);
                thumb.add_controller (click);

                click.released.connect ((n_press, x, y) => {
                    if (n_press >= 1) {
                        Gtk.Widget? w = click.get_widget ();
                        if (w is Gtk.Picture) {
                            var pic = (Gtk.Picture) w;
                            show_image.begin (imgcon.get_image_cache_path (url), url, pic);
                        }
                    }
                });

                imgcon.enqueue_image_download (url, thumb);
            }

            row_box.append (thumbs_box);
        }

        var row = new Gtk.ListBoxRow ();
        row.set_child (row_box);

        return row;
    }

    // 書き込み履歴を検査する
    private void mark_posthist () {
        string? board_key = FiveCh.Board.guess_board_key_from_url (url);
        string? site_base = FiveCh.Board.guess_site_base_from_url (url);
        string? threadkey = FiveCh.DatLoader.guess_threadkey_from_url (url);

        // リセット
        foreach (var p in posts) {
            p.mark = p.MarkType.NONE;
        }

        // check_status = 0のデータを探し、DBを更新する
        try {
            Db.DB db = new Db.DB ();

            var rows = db.query ("""
                SELECT *, rowid
                  FROM posthist
                 WHERE board_url = ?1
                   AND bbs_id = ?2
                   AND thread_id = ?3
                   AND check_status = 0
                 ORDER BY last_touch_date desc
            """, { site_base, board_key, threadkey });
            foreach (var r in rows) {
                for (int i = posts.size - 1; i >= old_count; --i) {
                    if (posts[i].body != r["text"]) {
                        continue;
                    }

                    // マークということにする
                    var sql = """
                            UPDATE posthist
                               SET post_index = ?1,
                                   check_status = 1
                             WHERE rowid = ?2
                    """;
                    db.exec (sql, { (i + 1).to_string (), r["rowid"] });
                    break;
                }
            }
        } catch (Error e) {
            win.show_error_toast (e.message);
        }

        // マークされていたらそのステータスを持つ
        try {
            Db.DB db = new Db.DB ();

            var rows = db.query ("""
                SELECT *, rowid
                  FROM posthist
                 WHERE board_url = ?1
                   AND bbs_id = ?2
                   AND thread_id = ?3
                   AND check_status = 1
                 ORDER BY post_index asc
            """, { site_base, board_key, threadkey });
            foreach (var r in rows) {
                var p = posts[int.parse (r["post_index"]) - 1];
                p.mark = ResRow.ResItem.MarkType.MINE;

                // これに対してのレスもマーク
                var reps = replied_from[int.parse (r["post_index"])];
                foreach (var rep in reps) {
                    var rp = posts[(int) rep-1];
                    if (rp.mark == ResRow.ResItem.MarkType.NONE)
                        rp.mark = ResRow.ResItem.MarkType.REPLY;
                }
            }
        } catch (Error e) {
            win.show_error_toast (e.message);
        }
    }

    // 画像拡大表示用の簡易ビューアに遷移する
    private async void show_image (string cache_path, string url, Gtk.Picture thumb) {

        if (!FileUtils.test (cache_path, FileTest.EXISTS)) {
            imgcon.load_image_thumbnail_async (url, thumb, true);
            return;
        }
        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        nav.push (new imageview (url, cache_path));
    }

    private async void add (int index) {
        var window = this.get_ancestor (typeof (Gtk.Window)) as Gtk.Window;
        var popup = new new_res (window, g_app, url, index);
        popup.submitted.connect (() => {
            // 終わったら再読み込み
            this.reload.begin ();
        });
        popup.present ();
    }

    // argで指定されたものをコピー
    private async void copy (string arg) {
        StringBuilder sb = new StringBuilder ();

        int r;
        if (clicked_indexes.is_empty) {
            r = (int) right_clicked_row;
        } else {
            r = (int) clicked_indexes[(int) right_clicked_row - 1];
        }

        var p = posts[r - 1];

        // 名前を戻す
        Pango.AttrList attrs;
        string plain;
        unichar accel_char;

        string clean_name;
        try {
            Pango.parse_markup (p.name, -1, '_',
                                out attrs, out plain, out accel_char);
            clean_name = plain;
        } catch (Error e) {
            clean_name = p.name;
        }


        switch (arg) {
        case "url" :
            sb.append (DatLoader.build_browser_url (url) + r.to_string ());
            break;
        case "name":
            sb.append (clean_name);
            break;
        case "ID":
            sb.append (p.id);
            break;
        case "text":
            sb.append (p.body);
            break;
        case "set":
            sb.append (r.to_string ()).append (" ");
            sb.append (clean_name).append (" ");
            sb.append (p.mail).append (" ");
            sb.append (p.date).append (" ");
            sb.append (p.id).append ("\n");
            sb.append (p.body);
            break;
        case "thread_url":
            sb.append (DatLoader.build_browser_url (url));
            break;
        case "subject":
            sb.append (this.name);
            break;
        default:
            return;
        }

        common.copy_to_clipboard (sb.str);
        win.show_error_toast (_("Copied."));
    }

    private async void go_up () {
        scroll_to_post (1);
    }

    private async void go_down () {
        if (is_read || read == 0) {
            scroll_to_post (posts.size);
        } else {
            scroll_to_post (read);
            is_read = true;
        }
    }

    private async void search (string target) {
        open_search_page (entry_search.text);
    }

    [GtkCallback]
    private void on_add_click () {
        add.begin (-1);
    }

    [GtkCallback]
    private void on_reload_click () {
        reload.begin ();
    }

    [GtkCallback]
    private void on_up_click () {
        go_up.begin ();
    }

    [GtkCallback]
    private void on_down_click () {
        go_down.begin ();
    }

    [GtkCallback]
    private void on_search () {
        if (entry_search.text == "")
            return;
        search.begin (entry_search.text);
    }

    private void on_top_activate () {

        string? board_key = FiveCh.Board.guess_board_key_from_url (url);
        string? site_base = FiveCh.Board.guess_site_base_from_url (url);
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        common.open_url (site_base + board_key + "/", nav);
    }

    private void on_reply_activate () {
        int r;
        if (clicked_indexes.is_empty) {
            r = (int) right_clicked_row;
        } else {
            r = (int) clicked_indexes[(int) right_clicked_row - 1];
        }
        add.begin (r);
    }

    private void on_copy_activate (Variant? param) {
        string arg = param.get_string ();
        copy.begin (arg);
    }

    private async void on_mark_activate () {
        string? board_key = FiveCh.Board.guess_board_key_from_url (url);
        string? site_base = FiveCh.Board.guess_site_base_from_url (url);
        string? threadkey = FiveCh.DatLoader.guess_threadkey_from_url (url);

        int r = (int) right_clicked_row;

        var p = posts[r - 1];

        // マーク解除
        if (p.mark == p.MarkType.MINE) {
            p.mark = p.MarkType.NONE;
            try {
                Db.DB db = new Db.DB ();
                var sql = """
                        DELETE FROM posthist
                        WHERE board_url = ?1
                          AND bbs_id = ?2
                          AND thread_id = ?3
                          AND post_index = ?4
                    """;
                db.exec (sql, { site_base, board_key, threadkey, r.to_string () });
            } catch (Error e) {
                win.show_error_toast (e.message);
            }
        } else {
            p.mark = p.MarkType.MINE;
            try {
                Db.DB db = new Db.DB ();
                var sql = """
                        INSERT INTO posthist (board_url, bbs_id, thread_id, post_index, check_status, text, last_touch_date)
                        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                """;
                db.exec (sql, { site_base, board_key, threadkey, r.to_string (), "1", p.body, new DateTime.now_utc ().to_unix ().to_string () });
            } catch (Error e) {
                win.show_error_toast (e.message);
            }
        }

        yield reload (true);

        if (replies_view == null) return;


        switch (rep_type) {
            case replies.Type.ID:
                replies_view.set_listbox (create_id_listbox (rep_id));
                break;
            case replies.Type.REPLIES:
                replies_view.set_listbox (create_reply_tree_listbox (rep_root_index));
                break;
        }
    }
}

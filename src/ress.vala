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

    Semboola.Window win;

    private DatLoader loader;

    private GLib.ListStore store = new GLib.ListStore (typeof (ResRow.ResItem));
    private Gee.ArrayList<ResRow.ResItem> posts;

    // 初期化フラグ
    private bool initialized = false;

    // ここまでロード
    private int res_count = 0;

    [GtkChild]
    unowned Gtk.ListBox listview;

    public RessView (string url, string name) {
        // Object(
        //     title:name
        // );
        //
        this.url = url;
        this.name = name;

        loader = new DatLoader ();

        // var selection = new Gtk.SingleSelection (store);
        // selection.autoselect = false;
        // selection.can_unselect = true;

        // var factory = new Gtk.SignalListItemFactory ();
        // factory.setup.connect (on_factory_setup);
        // factory.bind.connect (on_factory_bind);

        // listview.model = selection;
        // listview.factory = factory;


        // bind_model 使用
        // listview.bind_model (store, (obj) => {
            // var post = (ResRow.ResItem) obj;

            // var row_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            // row_box.margin_top = 6;
            // row_box.margin_bottom = 6;
            // row_box.margin_start = 8;
            // row_box.margin_end = 16;

            // var header = new Gtk.Label (null);
            // header.use_markup = true;
            // header.xalign = 0.0f;
            // header.wrap = true;
            // header.wrap_mode = Pango.WrapMode.WORD_CHAR;
            //header.ellipsize = Pango.EllipsizeMode.END;

            // var body = new ClickableLabel ();

            // ここで span イベント接続（ListView版と同じノリ）
            // body.span_left_clicked.connect ((span) => {
            //     on_span_left_clicked (post, span);
            // });
            // body.span_right_clicked.connect ((span, x, y) => {
            //     on_span_right_clicked (post, span, x, y, body);
            // });

            // ★ここが抜けてた：中身を row_box に入れる
            // row_box.append (header);
            // row_box.append (body);

            // 中身セット
            // set_post_widgets (post, header, body);

            // var row = new Gtk.ListBoxRow ();
            // row.set_child (row_box);
            // return row;
        // });
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

    private void set_post_widgets (ResRow.ResItem post, Gtk.Label header, ClickableLabel body) {
        string safe_name = Markup.escape_text (post.name);
        string safe_date = Markup.escape_text (post.date);
        string id_part = (post.id != "")
            ? @" <span foreground='#c03030'>ID:$(Markup.escape_text (post.id))</span>"
            : "";

        header.set_markup (@"<b>$(post.index)</b> $safe_name  $safe_date$id_part");

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

    private void rebuild_listbox_incremental () {
        //clear_listbox ();

        int i = res_count;
        Idle.add (() => {
        // Timeout.add (100, () => { // テスト用
            // 1回のIdleで20行
            int chunk = 20;
            for (int n = 0; n < chunk && i < posts.size; n++, i++) {
                var post = posts[i];

                var row_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                row_box.margin_top = 6;
                row_box.margin_bottom = 6;
                row_box.margin_start = 8;
                row_box.margin_end = 8;

                var header = new Gtk.Label (null);
                header.use_markup = true;
                header.xalign = 0.0f;
                header.wrap = true;
                header.wrap_mode = Pango.WrapMode.WORD_CHAR;
                // header.ellipsize = Pango.EllipsizeMode.END;

                var body = new ClickableLabel ();


                set_post_widgets (post, header, body);

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

            res_count = i;

            // まだ残ってれば次のIdleでもう少し作る
            return i < posts.size;
        });
    }

    private void clear_listbox () {
        Gtk.Widget? child = listview.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            listview.remove (child);
            child = next;
        }
    }

    private async void reload () {
        this.title=_("Loading...");
        try {
            var cancellable = new Cancellable ();
            posts = yield loader.load_from_url_async (url, cancellable);

            rebuild_listbox_incremental ();

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
        default:
            break;
        }
    }

    private void on_span_right_clicked (ResRow.ResItem post, Span span, double x, double y, Gtk.Widget widget) {
        switch (span.type) {
        case SpanType.REPLY:
            if (span.payload != null) {
                try {
                    uint target = (uint) int.parse (span.payload);
                    scroll_to_post (target);
                } catch (Error e) {}
            }
            break;
        case SpanType.URL:
            if (span.payload != null) {
                try {
                    var launcher = new Gtk.UriLauncher (span.payload);
                    Gtk.Window? parent = this.get_root () as Gtk.Window;
                    launcher.launch.begin (parent, null);
                } catch (Error e) {}
            }
            break;
        default:
            break;
        }
    }


    private void scroll_to_post (uint index) {
        // ResRow.ResItem.index == 表示番号として検索
        // for (uint i = 0; i < store.get_n_items (); i++) {
        //     var p = (ResRow.ResItem) store.get_item (i);
        //     if (p.index == index) {
        //         listview.scroll_to (i, Gtk.ListScrollFlags.NONE, null);
        //         break;
        //     }
        // }
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

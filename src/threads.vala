/* threads.vala
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
using Gee;
using Gdk;
using Adw;
using FiveCh;
using Sqlite;

[GtkTemplate (ui = "/jp/lv34/Semboola/threads.ui")]
public class ThreadsView : Adw.NavigationPage {

    private string url;
    private string name;

    Semboola.Window win;

    // 初期化フラグ
    private bool initialized = false;

    private GLib.ListStore store = new GLib.ListStore (typeof (ThreadRow.ThreadsItem));
    private GLib.ListStore store_all = new GLib.ListStore (typeof (ThreadRow.ThreadsItem));

    private SimpleActionGroup page_actions;
    private SimpleAction bookmark_board_action;

    [GtkChild]
    unowned Gtk.ListView listview;

    [GtkChild]
    unowned Gtk.ToggleButton button_search;

    [GtkChild]
    unowned Gtk.SearchBar bar_search;

    [GtkChild]
    unowned Gtk.SearchEntry entry_search;



    public ThreadsView (string url, string name) {
        // Object(
        //     title:name
        // );
        //
        this.url = url;
        this.name = name;

        button_search.bind_property (
            "active",
            bar_search, "search-mode-enabled",
            BindingFlags.BIDIRECTIONAL
        );

        var model = new Gtk.NoSelection (store);

        var factory = new Gtk.SignalListItemFactory ();

        // アイテムが差し替わるたびにデータを流し込む
        factory.setup.connect ((obj) => {
            var list_item = (Gtk.ListItem) obj;
            var row = new ThreadRow ();
            list_item.set_child (row);

            // 行全体にクリックジェスチャを付与
            var click = new Gtk.GestureClick ();
            click.released.connect ((n_press, x, y) => {
                if (n_press == 1) {
                    // 現在の行位置を使ってアクティベーション発火
                    listview.activate (list_item.position);
                }
            });
            row.add_controller (click);
        });

        factory.bind.connect ((obj) => {
            var list_item = (Gtk.ListItem) obj;
            var row = (ThreadRow) list_item.get_child ();
            var t = (ThreadRow.ThreadsItem) list_item.get_item ();
            row.tname.set_text (t.title);
            row.spd.set_text("%.01f".printf (t.spd*24));
            var fmt = _("%Y-%m-%d %H:%M:%S");
            row.dtime.set_text (t.dtime.format (fmt));
            row.ress.set_text ("%d".printf (t.ress));
            if (t.unread != -1)
                row.unread.set_text (t.unread.to_string ());

            t.bind_property (
                "unread",
                row.unread,
                "label",
                BindingFlags.SYNC_CREATE
            );
            t.bind_property (
                "read",
                row.unread,
                "visible",
                BindingFlags.SYNC_CREATE
            );
            // t.bind_property (
            //     "favorite",
            //     row.favorite,
            //     "label",
            //     BindingFlags.SYNC_CREATE
            // );
        });

        listview.model = model;
        listview.factory = factory;

        // NavigationView に push されて画面に出る直前〜直後に呼ばれる
        this.shown.connect (() => {
            win = this.get_root() as Semboola.Window;
            init_load.begin ();
            load_threadlist.begin (); // 未読更新
        });
    }

    construct {
        typeof (ThreadRow).ensure ();

        page_actions = new SimpleActionGroup ();

        var copy_action = new SimpleAction ("copy_thread", VariantType.STRING);
        copy_action.activate.connect ((param) => {
            on_copy_activate (param);
        });
        page_actions.add_action (copy_action);

        // localrules アクション
        var localrules_action = new SimpleAction ("local_rules", null);
        localrules_action.activate.connect ((param) => {
            on_localrules_activate ();
        });
        page_actions.add_action (localrules_action);

        // bookmark_board アクション
        bookmark_board_action = new SimpleAction.stateful ("bookmark_board", null, new Variant.boolean (false));
        bookmark_board_action.activate.connect ((param) => {
        bool current = bookmark_board_action.state.get_boolean ();
        bookmark_board_action.set_state (new Variant.boolean (!current));

        on_bookmark_board_activate (!current);
        });
        page_actions.add_action (bookmark_board_action);

        // "win." プレフィックスでこのページに登録
        this.insert_action_group ("win", page_actions);

        // 行がアクティブ化されたとき（pos は行番号）
        listview.activate.connect (on_row_activated);
    }

    // 最初の読み込み
    private async void init_load () {
        // bookmark更新
        reload_bookmark();
        if (initialized) {
            return;
        }


        yield reload();

        initialized = true;
        yield load_threadlist (); // 未読更新
        copy_store ();
    }

    private async void all_reload () {
        yield reload();
        yield load_threadlist (); // 未読更新
        copy_store ();
    }

    // bookmark状態の確認
    private async void reload_bookmark() {
        Db.DB db = new Db.DB();

        var rows = db.query ("""
            SELECT 1
              FROM bbslist
             WHERE url = ?1
             ORDER BY name asc
        """, {url});

        if (rows.is_empty) {
            bookmark_board_action.set_state (new Variant.boolean (false));
        } else {
            bookmark_board_action.set_state (new Variant.boolean (true));
        }
    }

    // スレ一覧更新(非同期で呼ぶこと)
    private async void reload () {
        this.title=_("Loading...");
        try {
            var board  = new FiveCh.Board(Board.guess_site_base_from_url (url), Board.guess_board_key_from_url (url));
            var client = new FiveCh.Client();

            var list = yield client.fetch_subject_async(board);  // 非同期

            if (list.length() > 0) {
                store_all.remove_all ();
                foreach (var r in list) {
                    store_all.append (new ThreadRow.ThreadsItem (
                        r.title,
                        r.creation_datetime_local (),
                        r.ikioi_per_hour_now (),
                        r.count,
                        r.dat_url
                    ));
                }
            } else {
                win.show_error_toast (_("No threads found."));
            }
        } catch (Error e) {
            win.show_error_toast (_("Invalid error."));
            return;
        } finally {
            this.title=name;
        }
    }

    // 未読チェック
    private async void load_threadlist () {
        try {
            Db.DB db = new Db.DB();

            string sql = """
                SELECT *
                  FROM threadlist
                 WHERE board_url = ?1
                 AND bbs_id =?2
                 ORDER BY thread_id asc
            """;

            var rows = db.query (sql, {FiveCh.Board.guess_site_base_from_url (url), FiveCh.Board.guess_board_key_from_url (url)});

            // storeとrowsのマージ
            var index = new HashMap<string, HashMap<string, string>> ();
            foreach (var map in rows) {
                string? id = map.get ("thread_id");
                if (id == null)
                    continue;
                index[id] = map;
            }

            for (uint i = 0; i < store_all.get_n_items (); ++i) {
                var obj  = store_all.get_item (i);
                var item = obj as ThreadRow.ThreadsItem;
                HashMap<string, string>? extra = index.get (item.thread_id);

                if (extra == null)
                    continue; // ArrayList 側に情報なし

                // 必要なカラムを引いて反映
                string? v;

                v = extra.get ("current_res_count");
                item.readcnt = v.to_int ();
                item.unread = item.ress - v.to_int ();
                if (item.unread < 0) item.unread = 0;
                item.read = true;

                v = extra.get ("favorite");
                item.favorite = v.to_int ();
            }

        } catch (Error e) {
            print (e.message);
            win.show_error_toast (e.message);
        }
    }

    private void copy_store () {
        store.remove_all ();
        for (uint i = 0; i < store_all.get_n_items (); ++i) {
            store.append (store_all.get_item (i));
        }
    }

    private async void search (string target) {
        store.remove_all ();
        for (uint i = 0; i < store_all.get_n_items (); ++i) {
            var item = store_all.get_item (i) as ThreadRow.ThreadsItem;
            if (item.title.contains (target))
                store.append (store_all.get_item (i));
        }
    }

    // argで指定されたものをコピー
    private async void copy (string arg) {
        StringBuilder sb = new StringBuilder ();

        switch (arg) {
            case "url":
                sb.append (url);
                break;
            case "name":
                sb.append (name);
                break;
            case "set":
                sb.append (name).append ("\n");
                sb.append (url);
                break;
            default:
                return;
        }

        common.copy_to_clipboard (sb.str);
        win.show_error_toast (_("Copied."));
    }

    private void on_copy_activate (Variant? param) {
        string arg = param.get_string ();
        copy.begin (arg);
    }

    private void on_bookmark_board_activate (bool bm)
    {
        if (bm) {
            common.add_bbs_list.begin (url, win);
        } else {
            common.remove_bbs_list.begin (url, win);
        }
    }

    private void on_localrules_activate () {
        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        nav.push(new local_rules (url));
    }


    [GtkCallback]
    private void on_reload_click () {
        all_reload.begin ();
    }

    // 行クリック
    private void on_row_activated (uint pos) {
        var item = (ThreadRow.ThreadsItem) store.get_item ((int)pos);

        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        nav.push(new RessView (item.url, item.title, item.readcnt));
    }

    [GtkCallback]
    private void on_add_click () {
        var window = this.get_ancestor (typeof (Gtk.Window)) as Gtk.Window;
        var popup = new new_thread (window, g_app, new FiveCh.Board(Board.guess_site_base_from_url (url), Board.guess_board_key_from_url (url)));
        popup.submitted.connect (() => {
            // 終わったら再読み込み
            this.all_reload.begin ();
        });
        popup.present ();
    }

    [GtkCallback]
    private void on_search () {
        search.begin (entry_search.text);
    }

    [GtkCallback]
    private void on_search_toggle () {
        search.begin ("");
    }
}

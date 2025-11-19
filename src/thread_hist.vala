/* thread_hist.vala
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
using Adw;
using Sqlite;

[GtkTemplate (ui = "/jp/lv34/Semboola/thread_hist.ui")]
public class thread_hist : Adw.NavigationPage {

    Semboola.Window win;

    // 初期化フラグ
    private bool initialized = false;

    private GLib.ListStore store = new GLib.ListStore (typeof (ThreadRow.ThreadsItem));

    [GtkChild]
    unowned Gtk.ListView listview;

    public thread_hist () {

        var model = new Gtk.SingleSelection (store);
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
            //row.spd.set_text();
            row.dtime.set_text (t.url);
            row.ress.set_text ("%d".printf (t.ress));
            // if (t.unread != -1)
            //     row.unread.set_text (t.unread.to_string ());
            row.unread.set_visible (false);

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
        });
    }

    construct {
        typeof (ThreadRow).ensure ();

        // 行がアクティブ化されたとき（pos は行番号）
        listview.activate.connect (on_row_activated);
    }

    // 最初の読み込み
    private async void init_load () {
        if (initialized) {
            return;
        }
        initialized = true;
        yield load_threadlist (); // 未読更新
    }



    // 未読チェック
    private async void load_threadlist () {
        try {
            Db.DB db = new Db.DB();

            string sql = """
                SELECT *
                  FROM threadlist
                 ORDER BY last_touch_date desc
            """;

            var rows = db.query (sql, {});

            foreach (var r in rows) {
                store.append (new ThreadRow.ThreadsItem (
                    r["title"],
                    new DateTime.from_unix_local (int64.parse (r["last_touch_date"])),
                    -1,
                    int.parse (r["current_res_count"]),
                    r["board_url"] + r["bbs_id"] + "/dat/" +r["thread_id"] + ".dat"
                ));
            }

        } catch (Error e) {
            win.show_error_toast (_("Invalid error."));
        }
    }

    // 行クリック
    private void on_row_activated (uint pos) {
        var item = (ThreadRow.ThreadsItem) store.get_item ((int)pos);

        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        nav.push(new RessView (item.url, item.title));
    }
}

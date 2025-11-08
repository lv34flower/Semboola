/* window.vala
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

[GtkTemplate (ui = "/jp/lv34/Semboola/threads.ui")]
public class ThreadsView : Adw.NavigationPage {

    private string url;
    private string name;

    Semboola.Window win;

    private GLib.ListStore store = new GLib.ListStore (typeof (ThreadRow.ThreadsItem));

    [GtkChild]
    unowned Gtk.ListView listview;

    public ThreadsView (string url, string name) {
        // Object(
        //     title:name
        // );
        //
        this.url = url;
        this.name = name;

        var model = new Gtk.SingleSelection (store);

        var factory = new Gtk.SignalListItemFactory ();

        // アイテムが差し替わるたびにデータを流し込む
        factory.setup.connect ((obj) => {
            var list_item = (Gtk.ListItem) obj;
            var row = new ThreadRow ();
            list_item.set_child (row);
        });

        factory.bind.connect ((obj) => {
            var list_item = (Gtk.ListItem) obj;
            var row = (ThreadRow) list_item.get_child ();
            var t = (ThreadRow.ThreadsItem) list_item.get_item ();
            row.tname.set_text (t.title);
            row.spd.set_text("%.01f".printf (t.spd*24));
            var fmt = _("%Y-%m-%d %H:%M:%S");
            row.dtime.set_text (t.dtime.format (fmt));
            row.ress.set_text ("%5d".printf (t.ress));
        });

        listview.model = model;
        listview.factory = factory;

        // 行がアクティブ化されたとき（pos は行番号）
        // bd_list_boards.activate.connect (on_row_activated);

        // NavigationView に push されて画面に出る直前〜直後に呼ばれる
        this.shown.connect (() => {
            win = this.get_root() as Semboola.Window;
            init_load.begin ();
        });
    }

    static construct {
        typeof (ThreadRow).ensure ();
    }

    // 最初の読み込み
    private async void init_load () {
        this.title=_("Loading...");

        yield reload();

        this.title=name;
    }

    // スレ一覧更新(非同期で呼ぶこと)
    private async void reload () {
        try {
            var board  = new FiveCh.Board(Board.guess_site_base_from_url (url), Board.guess_board_key_from_url (url));
            var client = new FiveCh.Client(FiveCh.cookie);

            var list = yield client.fetch_subject_async(board);  // 非同期
            if (list.length() > 0) {
                store.remove_all ();
                foreach (var r in list) {
                    store.append (new ThreadRow.ThreadsItem (
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
        }
    }

    [GtkCallback]
    private void on_reload_click () {
        init_load.begin ();
    }

}

/* ng.vala
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
using Gdk;
using Adw;
using FiveCh;

[GtkTemplate (ui = "/jp/lv34/Semboola/ng.ui")]
public class nglist : Adw.NavigationPage {

    Semboola.Window win;

    private NgMode mode;

    private GLib.ListStore store;

    [GtkChild]
    private unowned Gtk.ToggleButton btn_thread;

    [GtkChild]
    private unowned Gtk.ToggleButton btn_id;

    [GtkChild]
    private unowned Gtk.ToggleButton btn_name;

    [GtkChild]
    private unowned Gtk.ToggleButton btn_word;

    [GtkChild]
    private unowned Gtk.ListView listview;

    public nglist () {
        // Object(
        //     title:name
        // );
        //
        //
        this.mode = NgMode.THREAD;

        // NavigationView に push されて画面に出る直前〜直後に呼ばれる
        this.shown.connect (() => {
            win = this.get_root() as Semboola.Window;
            load.begin ();
        });
    }

    construct {
        // モデルを作る
        store = new GLib.ListStore (typeof (ng_row_data));

        var selection = new Gtk.NoSelection (store);

        var factory = new Gtk.SignalListItemFactory ();

        factory.setup.connect ((obj) => {
            var list_item = (Gtk.ListItem) obj;

            var row = new ng_row ();
            list_item.set_child (row);
        });

        factory.bind.connect ((obj) => {
            var list_item = (Gtk.ListItem) obj;

            var row  = (ng_row) list_item.get_child ();
            var data = (ng_row_data) list_item.get_item ();

            row.bind (data);
        });

        listview.model   = selection;
        listview.factory = factory;

        listview.activate.connect (on_row_activated);
    }

    static construct {
    }

    private async void load () {
        store.remove_all ();

        // 初期読み込み
        try {
            Db.DB db = new Db.DB();

            string sql = """
                SELECT *, rowid
                  FROM ngtext
                 WHERE type = ?1
                 ORDER BY rowid asc
            """;

            var rows = db.query (sql, {((int) mode).to_string ()});

            foreach (var r in rows) {
                var text = r["text"];
                var board = r["board"];
                var enable = r["enable"] != "0";
                var regex = r["is_regex"] != "0";
                var rowid = r["rowid"].to_long ();

                store.append (new ng_row_data (text, enable, board, regex, rowid));
            }


        } catch (Error e) {
            print (e.message);
            win.show_error_toast (e.message);
        }
    }

    private void on_row_activated (uint pos) {
        var data = (ng_row_data) store.get_item ((int)pos);

        var window = this.get_ancestor (typeof (Gtk.Window)) as Gtk.Window;
        var popup = new ng_sub (window, g_app, mode, data.rowid, data.board, "");
        popup.submitted.connect (() => {
            // 終わったら再読み込み
            load.begin ();
        });
        popup.present ();
    }

    [GtkCallback]
    private void on_add_click () {
        string u = "";

        try {
            u = Board.build_board_url (win.url);
        } catch {
            // 捨てる
        }

        var window = this.get_ancestor (typeof (Gtk.Window)) as Gtk.Window;
        var popup = new ng_sub (window, g_app, mode, -1, u, "");
        popup.submitted.connect (() => {
            // 終わったら再読み込み
            load.begin ();
        });
        popup.present ();
    }

    [GtkCallback]
    private void on_tab_change (Gtk.ToggleButton btn) {

        if (!btn.active) {
            // OFF になったタイミングは無視したいなら return
            return;
        }

        if (btn == btn_thread)
            mode = NgMode.THREAD;
        else if (btn == btn_id)
            mode = NgMode.ID;
        else if (btn == btn_word)
            mode = NgMode.WORD;
        else if (btn == btn_name)
            mode = NgMode.NAME;

        load.begin ();
    }

    [GtkCallback]
    private void on_editmode () {

    }
}

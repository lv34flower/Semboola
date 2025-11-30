/* replies.vala
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

[GtkTemplate (ui = "/jp/lv34/Semboola/replies.ui")]
public class replies : Adw.NavigationPage {
    public enum Type {
        NONE,
        ID,
        REPLIES,
        SEARCH,
    }

    private string name;

    Semboola.Window win;

    [GtkChild]
    unowned Gtk.ScrolledWindow listwindow;

    // 前の画面から渡すことが前提
    Gtk.ListBox listview;

    public replies (string name, Gtk.ListBox l) {
        // Object(
        //     title:name
        // );
        //
        this.name = name;
        this.listview = l;

        this.title=name;

        listwindow.set_child (listview);

        // NavigationView に push されて画面に出る直前〜直後に呼ばれる
        this.shown.connect (() => {
            win = this.get_root() as Semboola.Window;
            init_load.begin ();
        });
    }

    static construct {
        typeof (ResRow).ensure ();
    }

    private async void init_load () {

    }

    public void set_listbox (Gtk.ListBox c) {
        listwindow.set_child (c);
    }
}

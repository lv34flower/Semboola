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

[GtkTemplate (ui = "/jp/lv34/Semboola/window.ui")]
public class Semboola.Window : Adw.ApplicationWindow {

    public class BoardsItem : Object {
        public string title { get; set; }
        public string url  { get; set; }

        public BoardsItem (string t, string u) {
            title = t;
            url = u;
        }
    }

    [GtkChild]
    unowned Adw.ToastOverlay toast;

    [GtkChild]
    unowned Adw.NavigationView nav;

    public Window (Gtk.Application app) {
        Object (application: app);
    }

    static construct {
        typeof (BoardsView).ensure ();
    }

    protected override void constructed () {
        base.constructed();
        nav.push (new BoardsView ());
    }

    // エラー表示
    public void show_error_toast (string message) {
        var t = new Adw.Toast (message);
        t.set_timeout (3); // 秒

        // 重要度を上げたいなら（キューで優先されます）
        t.set_priority (Adw.ToastPriority.HIGH);
        toast.add_toast (t);
    }
}

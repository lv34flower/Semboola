/* add_board.vala
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

[GtkTemplate (ui = "/jp/lv34/Semboola/add_board.ui")]
public class AddBoardWindow : Adw.ApplicationWindow {
    public signal void submitted (string text);

    [GtkChild]
    private unowned Gtk.Entry entry;
    [GtkChild]
    private unowned Gtk.Button button_submit;
    [GtkChild]
    private unowned Gtk.Button button_cancel;

    public AddBoardWindow (Gtk.Window parent, Adw.Application app) {
        Object (application: app, transient_for: parent);
        this.set_modal (true);
    }

    construct {
        button_submit.clicked.connect (() => {
            submitted (entry.text);
            this.close ();
        });

        button_cancel.clicked.connect (() => {
            this.close ();
        });
    }
}

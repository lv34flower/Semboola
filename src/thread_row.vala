/* thread_row.vala
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

using GLib;

[GtkTemplate (ui = "/jp/lv34/Semboola/thread_row.ui")]
public class ThreadRow : Gtk.ListBoxRow {

    [GtkChild] public unowned Gtk.Label tname;
    [GtkChild] public unowned Gtk.Label dtime;
    [GtkChild] public unowned Gtk.Label spd;
    [GtkChild] public unowned Gtk.Label ress;

    public class ThreadsItem : Object {
        public string title { get; set; }
        public DateTime dtime { get; set; }
        public double spd  { get; set; }
        public int ress  { get; set; }
        public string url { get; set; }

        public ThreadsItem (string t, DateTime d, double s, int r, string u) {
            title=t;
            dtime=d;
            spd=s;
            ress=r;
            url=u;
        }
    }
}

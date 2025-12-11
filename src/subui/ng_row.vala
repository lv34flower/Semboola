/* ng_row.vala
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
 * GNU General Public License for more details.e
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gtk;

public class ng_row_data : Object {
    public string text { get; set; }
    public bool enable { get; set; }
    public string board { get; set; }
    public bool regex { get; set; }
    public long rowid { get; set; }

    public ng_row_data (string text, bool enable, string board, bool regex, long rowid) {
        this.text = text;
        this.enable = enable;
        this.board = board;
        this.regex = regex;
        this.rowid = rowid;
    }
}

[GtkTemplate (ui = "/jp/lv34/Semboola/subui/ng_row.ui")]
public class ng_row : Gtk.Box {

    [GtkChild]
    private unowned Gtk.Label label_text;

    [GtkChild]
    private unowned Gtk.Label label_enable;

    [GtkChild]
    private unowned Gtk.Label label_board;

    [GtkChild]
    private unowned Gtk.Label label_regex;

    private long rowid;

    public void bind (ng_row_data data) {
        label_text.label = data.text;
        label_board.label = data.board;

        if (data.regex)
            label_regex.visible = true;
        else
            label_regex.visible = false;
        if (data.enable)
            label_enable.label = _("Enabled");
        else
            label_enable.label = _("Disabled");
    }
}


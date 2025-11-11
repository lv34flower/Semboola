/* res_row.vala
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

public class ResRow : Gtk.Box {
    public class ResItem : Object {
        public uint index { get; construct; }
        public string name { get; construct; }
        public string mail { get; construct; }
        public string date { get; construct; }
        public string id { get; construct; }
        public string body { get; construct; }

        public ResItem(uint index,
                       string name,
                       string mail,
                       string date,
                       string id,
                       string body) {
            Object(index: index, name: name, mail: mail, date: date, id: id, body: body);
        }

        // キャッシュ
        private Gee.ArrayList<Span>? _spans;

        public Gee.ArrayList<Span> get_spans () {
            if (_spans == null) {
                _spans = FiveCh.SpanBuilder.build (body);
            }
            return _spans;
        }
    }
}


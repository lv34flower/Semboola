/* img_upload.vala
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

[GtkTemplate (ui = "/jp/lv34/Semboola/subui/img_upload.ui")]
public class img_upload : Adw.ApplicationWindow {

    Semboola.Window win;
    public signal void submitted (string urls);

    private ListModel model_files;

    private uint pulse_id = 0;

    [GtkChild] private unowned Gtk.Label label_msg;
    [GtkChild] private unowned Gtk.Button btn_cancel;
    [GtkChild] private unowned Gtk.ProgressBar bar;

    public img_upload (Gtk.Window parent, Adw.Application app) {

        Object (application: app, transient_for: parent);

        win = parent as Semboola.Window;

        init.begin ();
    }

    private async void init () {

        CatboxClient client = new CatboxClient ();

        string ret = "";
        var dialog = new Gtk.FileDialog ();
        dialog.title = _("Select Image");

        try {

            var filter = new Gtk.FileFilter ();
            filter.add_mime_type ("image/png");
            filter.add_mime_type ("image/jpeg");
            filter.add_mime_type ("image/webp");
            filter.add_mime_type ("image/gif");

            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            filters.append (filter);

            dialog.filters = filters;
            dialog.default_filter = filter;
            // 複数選択
            model_files = yield dialog.open_multiple (this, null);

            btn_cancel.sensitive = true;
            start_busy_ui ();
            label_msg.label = _("Uploading...");

            for (uint i = 0; i < model_files.get_n_items (); i++) {
                var file = model_files.get_item (i) as File;
                if (file == null) continue;

                ret = ret + "\n" + yield client.upload (file);
            }

            stop_busy_ui ();

            submitted (ret);

            this.close ();

        } catch (Error e) {
            win.show_error_toast (e.message);
            this.close ();
        }
    }

    private void start_busy_ui () {

        bar.set_pulse_step (0.03);
        if (pulse_id == 0) {
            pulse_id = Timeout.add (60, () => {
                bar.pulse ();
                return true;
            });
        }
    }

    private void stop_busy_ui () {
        if (pulse_id != 0) {
            Source.remove (pulse_id);
            pulse_id = 0;
        }
    }
}

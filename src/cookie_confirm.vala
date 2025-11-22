/* cookie_confirm.vala
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
using Adw;
using WebKit;

[GtkTemplate (ui = "/jp/lv34/Semboola/cookie_confirm.ui")]
public class cookie_confirm : Adw.ApplicationWindow {

    public signal void repost ();

    [GtkChild]
    private unowned WebKit.WebView webview;

    private string html;
    private string base_uri;

    public cookie_confirm (Gtk.Window parent, Adw.Application app, string h, string bu) {
        Object (application: app, transient_for: parent);
        this.set_modal (true);

        html = h;
        base_uri = bu;

        WebKit.NetworkSession session = webview.network_session;
        WebKit.CookieManager cookie_manager = session.get_cookie_manager ();

        cookie_manager.set_persistent_storage (
            FiveCh.cookie,
            WebKit.CookiePersistentStorage.TEXT
        );

        // テンプレート(=webview)が生えた後で呼ばれる
        webview.load_html (html, base_uri);
    }

    [GtkCallback]
    public void on_cancel_click () {
        this.close ();
    }

    [GtkCallback]
    public void on_post_click () {
        repost ();
        this.close ();
    }

}

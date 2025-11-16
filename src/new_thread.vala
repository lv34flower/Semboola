/* new_thread.vala
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

[GtkTemplate (ui = "/jp/lv34/Semboola/new_thread.ui")]
public class new_thread : Adw.ApplicationWindow {
    Semboola.Window win;
    public signal void submitted ();

    [GtkChild]
    private unowned Adw.EntryRow name;

    [GtkChild]
    private unowned Adw.EntryRow mail;

    [GtkChild]
    private unowned Adw.EntryRow title;

    [GtkChild]
    private unowned Gtk.TextView text;

    [GtkChild]
    private unowned Gtk.TextBuffer textbuffer;

    private FiveCh.Board board;

    public new_thread (Gtk.Window parent, Adw.Application app, FiveCh.Board _board) {
        Object (application: app, transient_for: parent);
        board = _board;
        this.set_modal (true);

        win = parent as Semboola.Window;

    }

    construct {

    }

    [GtkCallback]
    public void on_cancel_click () {
        this.close ();
    }

    [GtkCallback]
    public void on_post_click () {
        post.begin ();
    }

    public async void post () {
        var client = new FiveCh.Client (FiveCh.cookie);
        FiveCh.Client.PostResult? res;
        try {
            var opt = new FiveCh.PostOptions ();
            opt.submit_label = "新規スレッド作成";
            res = yield client.post_with_analysis_async (board,
                                                                    board.board_key,   // bbs
                                                                    null, // key
                                                                    textbuffer.text, //text
                                                                    name.text,   //name
                                                                    mail.text,  //mail
                                                                    title.text,  //subject
                                                                    opt
                                                                    );
        } catch (Error e) {
            win.show_error_toast (_("Invalid error."));
            return;
        }

        // 分岐
        if (res == null) {
            win.show_error_toast (_("Invalid error."));
            return;
        }
        switch (res.kind) {
        case FiveCh.Client.PostPageKind.OK:
            // 普通に成功
            stdout.printf ("posted ok\n");
            this.close ();
            break;

        case FiveCh.Client.PostPageKind.ERROR:
            // エラー表示
            stderr.printf ("post error: %s\n", res.error_message ?? "(unknown)");
            break;

        case FiveCh.Client.PostPageKind.CONFIRM:
            // 初回・クッキー・書き込み確認
            // res.confirm_message や res.message をダイアログに表示して、
            // ユーザーに本当に書き込むか聞く
            //bool user_ok = show_confirm_dialog (res);  // ←ここは自分で実装
            //if (!user_ok) break;

            if (res.confirm_form == null) {
                // フォームが取れなかったので諦める（あるいは HTML をそのまま見せる）
                break;
            }

            // ユーザーがOKを押したら、確認フォームを使って2回目POST

            break;
        }
        submitted ();

    }
}

/* new_res.vala
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

[GtkTemplate (ui = "/jp/lv34/Semboola/new_res.ui")]
public class new_res : Adw.ApplicationWindow {
    Semboola.Window win;
    public signal void submitted ();

    [GtkChild]
    private unowned Adw.EntryRow name;

    [GtkChild]
    private unowned Adw.EntryRow mail;

    [GtkChild]
    private unowned Gtk.TextView text;

    [GtkChild]
    private unowned Gtk.TextBuffer textbuffer;

    private string url;
    private FiveCh.Board board;

    public new_res (Gtk.Window parent, Adw.Application app, string u, int index) {
        Object (application: app, transient_for: parent);
        url = u;
        board  = new FiveCh.Board(FiveCh.Board.guess_site_base_from_url (url), FiveCh.Board.guess_board_key_from_url (url));
        this.set_modal (true);

        win = parent as Semboola.Window;

        // 既に入力中の内容が存在したら使用する
        try {
            Db.DB db = new Db.DB();

            string sql = """
                SELECT *
                  FROM tempwrite
                 WHERE board_url = ?1
                   AND bbs_id = ?2
                   AND thread_id = ?3
            """;

            var rows = db.query (sql, {board.site_base_url, board.board_key, FiveCh.DatLoader.guess_threadkey_from_url (url)});

            foreach (var r in rows) {
                name.set_text (r["name"]);
                mail.set_text (r["mail"]);
                textbuffer.set_text (r["text"]);
                break;
            }

            if (index > 0) {
                textbuffer.text = textbuffer.text + ">>%d\n".printf (index);
            }

        } catch (Error e) {
            win.show_error_toast (e.message);
            print(e.message);
        }
    }

    construct {

    }

    [GtkCallback]
    public void on_cancel_click () {
        // 入力中の内容を保管
        try {
            Db.DB db = new Db.DB();

            string sql = """
                INSERT INTO tempwrite (board_url, bbs_id, thread_id, title, name, mail, text, last_touch_date)
                VALUES (?1, ?2, ?3, '', ?4, ?5, ?6, ?7)
                ON CONFLICT(board_url, bbs_id, thread_id) DO UPDATE SET
                title = excluded.title,
                name = excluded.name,
                mail = excluded.mail,
                text = excluded.text,
                last_touch_date = excluded.last_touch_date
            """;

            db.exec (sql, {board.site_base_url, board.board_key, FiveCh.DatLoader.guess_threadkey_from_url (url), name.text, mail.text, textbuffer.text, new DateTime.now_utc ().to_unix ().to_string () });
        } catch (Error e) {
            win.show_error_toast (e.message);
            print(e.message);
        }

        this.close ();
    }

    [GtkCallback]
    public void on_post_click () {
        this.set_sensitive (false); // 操作不可にします
        post.begin ();
    }

    public async void post () {
        try {
            var client = new FiveCh.Client ();
            FiveCh.Client.PostResult? res;
            try {
                var opt = new FiveCh.PostOptions ();
                opt.submit_label = "書き込む";
                res = yield client.post_with_analysis_async (board,
                                                            board.board_key,   // bbs
                                                            FiveCh.DatLoader.guess_threadkey_from_url (url), // key
                                                            textbuffer.text, //text
                                                            name.text,   //name
                                                            mail.text,  //mail
                                                            null,  //subject
                                                            opt
                                                            );
            } catch (Error e) {
                //win.show_error_toast (_("Invalid error."));
                win.show_error_toast (e.message);
                print(e.message);
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
                try {
                    // 入力中情報の削除
                    Db.DB db = new Db.DB();
                    string sql = """
                        DELETE from tempwrite
                        where board_url = ?1
                          and bbs_id = ?2
                          and thread_id = ?3
                    """;

                    db.exec (sql, {board.site_base_url, board.board_key, FiveCh.DatLoader.guess_threadkey_from_url (url)});
                } catch (Error e) {
                    win.show_error_toast (e.message);
                    print(e.message);
                }
                submitted ();
                this.close ();
                break;

            case FiveCh.Client.PostPageKind.ERROR:
            case FiveCh.Client.PostPageKind.CONFIRM:
                // エラーまたは確認
                var window = this.get_ancestor (typeof (Gtk.Window)) as Gtk.Window;
                var popup = new cookie_confirm (window, g_app, res.html, board.bbs_cgi_url ());
                popup.repost.connect (() => {
                    post.begin ();
                });
                popup.present ();

                break;
            }
        } finally {
            this.set_sensitive (true); // 最後は操作可能にする
        }
    }
}

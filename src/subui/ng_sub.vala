/* ng_sub.vala
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
using FiveCh;

public enum NgMode {
    ID,
    NAME,
    WORD,
    THREAD,
}

[GtkTemplate (ui = "/jp/lv34/Semboola/subui/ng_sub.ui")]
public class ng_sub : Adw.ApplicationWindow {

    Semboola.Window win;
    public signal void submitted ();

    private long rowid;
    private string table_name;
    private NgMode mode;

    [GtkChild]
    private unowned Gtk.Label label_title;

    [GtkChild]
    private unowned Gtk.TextBuffer textbuffer;

    [GtkChild]
    private unowned Gtk.CheckButton chk_enable;

    [GtkChild]
    private unowned Gtk.CheckButton chk_regex;

    [GtkChild]
    private unowned Gtk.Label label_bbsname;

    [GtkChild]
    private unowned Gtk.CheckButton chk_onlyfor;

    [GtkChild]
    private unowned Gtk.Entry entry_url;


    public ng_sub (Gtk.Window parent, Adw.Application app, NgMode mode, long rowid, string board_url = "", string text = "") {
        Object (application: app, transient_for: parent);
        this.rowid = rowid;
        textbuffer.text = text;
        entry_url.text = board_url;
        this.mode = mode;

        win = parent as Semboola.Window;

        string u = "";

        if (board_url == "ALL") {
            try {
                u = Board.build_board_url (win.url);
            } catch {
                // 捨てる
            }
        }

        switch (mode) {
            case NgMode.ID:
                label_title.set_text ("ID");
                table_name = "ngid";
                break;
            case NgMode.NAME:
                label_title.set_text ("Name");
                table_name = "ngname";
                break;
            case NgMode.WORD:
                label_title.set_text ("Keyword");
                table_name = "ngtext";
                break;
            case NgMode.THREAD:
                label_title.set_text ("Thread");
                table_name = "ngthread";
                break;
        }

        if (rowid < 0) return;

        try {
            Db.DB db = new Db.DB();

            var rows = db.query ("""
                SELECT ngtext.*, bbslist.name as name, ngtext.rowid
                  FROM ngtext
             LEFT JOIN bbslist on bbslist.url = ngtext.board
                 WHERE ngtext.rowid = ?1
                   AND ngtext.type = ?2
            """, {rowid.to_string (), ((int)mode).to_string ()});

            foreach (var r in rows) {
                textbuffer.text = r["text"];
                chk_enable.active = r["enable"] != "0";
                chk_regex.active = r["is_regex"] != "0";

                if (entry_url.text == "ALL") {
                    entry_url.text = u;
                    chk_onlyfor.active = false;
                }
                else {
                    entry_url.text = r["board"];
                    chk_onlyfor.active = true;
                }
                label_bbsname.label = r["name"];

                break;
            }

        } catch (Error e) {
            win.show_error_toast (e.message);
        }

        // 最後に更新
        change_boardname.begin ();
    }

    construct {

    }

    [GtkCallback]
    private void on_delete_click () {
        try {
            Db.DB db = new Db.DB();

            var sql = """
                DELETE FROM ngtext
                WHERE rowid = ?1
            """;
            db.exec (sql, {rowid.to_string ()});
        } catch (Error e) {
            win.show_error_toast (e.message);
        }
        submitted ();
        this.close ();
    }

    [GtkCallback]
    private void on_cancel_click () {
        this.close ();
    }

    [GtkCallback]
    private void on_save_click () {
        if (textbuffer.text == "") {
            this.close ();
            return;
        }
        try {
            Db.DB db = new Db.DB();

            if (rowid < 0) {
                // 新規登録
                string sql = """
                    INSERT INTO ngtext (enable, text, type, is_regex, hide, chain, board)
                    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                """;

                db.exec (sql, {
                    ((int) chk_enable.active).to_string (),
                    textbuffer.text,
                    ((int) mode).to_string (),
                    ((int) chk_regex.active).to_string (),
                    "0",
                    "0",
                    chk_onlyfor.active ? entry_url.text : "ALL"
                });
            } else {
                // 既存行のアップデート
                string sql = """
                    UPDATE ngtext set enable=?1, text=?2, type=?3, is_regex=?4, hide=?5, chain=?6, board=?7
                    WHERE rowid = ?8
                """;

                db.exec (sql, {
                    ((int) chk_enable.active).to_string (),
                    textbuffer.text,
                    ((int) mode).to_string (),
                    ((int) chk_regex.active).to_string (),
                    "0",
                    "0",
                    chk_onlyfor.active ? entry_url.text : "ALL",
                    rowid.to_string ()
                });
            }
        } catch (Error e) {
            win.show_error_toast (e.message);
        }

        submitted ();
        this.close ();
    }

    private async void change_boardname () {
        try {
            Db.DB db = new Db.DB();

            var rows = db.query ("""
                SELECT *
                  FROM bbslist
                 WHERE url = ?1
            """, {entry_url.text});

            foreach (var r in rows) {
                label_bbsname.label = r["name"];
                return;
            }

            label_bbsname.label = "";

        } catch (Error e) {
            win.show_error_toast (e.message);
        }
    }

    [GtkCallback]
    private void on_url_change () {
        change_boardname.begin ();
    }

}

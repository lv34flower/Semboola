/* boards.vala
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
using Adw;
using Gee;

// 編集中,.
public class UiState : Object {
    public bool edit_mode { get; set; default = false; }
}

[GtkTemplate (ui = "/jp/lv34/Semboola/boards.ui")]
public class BoardsView : Adw.NavigationPage {

    public class BoardsItem : Object {
        public string title { get; set; }
        public string url  { get; set; }

        public BoardsItem (string t, string u) {
            title = t;
            url = u;
        }
    }

    [GtkChild]
    unowned Gtk.Button bd_button_add;
    [GtkChild]
    unowned Gtk.Button bd_button_hist;
    [GtkChild]
    unowned Gtk.ListView bd_list_boards;
    [GtkChild]
    unowned Gtk.ToggleButton bd_toggle_edit;

    // モデル（可変長）：GListStore<BoardsItem> + NoSelection
    private GLib.ListStore store = new GLib.ListStore (typeof (BoardsItem));

    // 編集状態管理
    private UiState ui_state = new UiState ();

    // 2行レイアウトのFactory：タイトル（太字＋省略）＋説明（サブ）
    private SignalListItemFactory factory = new SignalListItemFactory ();

    // 初期化,.
    public override void constructed () {
        base.constructed ();

        // ボタン押したとき
        bd_button_add.clicked.connect (on_button_add);
        bd_button_hist.clicked.connect (on_button_hist);

        bbslist();

        var sel = new NoSelection (store);
        bd_list_boards.model = sel;

        factory.setup.connect (on_setup);
        factory.bind.connect (on_bind);

        // 編集ボタンで edit_mode
        bd_toggle_edit.clicked.connect (() => {
            ui_state.edit_mode = !ui_state.edit_mode;
        });

        bd_list_boards.factory = factory;

        this.shown.connect (() => {
            clean_data.begin ();
        });
    }

    construct {
        typeof (ThreadsView).ensure ();

        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect (on_setup);
        factory.bind.connect  (on_bind);
        bd_list_boards.factory = factory;

        // 行がアクティブ化されたとき（pos は行番号）
        bd_list_boards.activate.connect (on_row_activated);
    }

    // リスト初期化,.
    private void on_setup (Gtk.SignalListItemFactory f, GLib.Object obj) {
        var li = (Gtk.ListItem) obj;

        // 行コンテナ（横並び）
        var hbox = new Box (Orientation.HORIZONTAL, -5);
        //hbox.margin_top = 6; hbox.margin_bottom = 6;
        hbox.add_css_class ("row");   // ← CSSで padding を与える
        //hbox.margin_start = 10; hbox.margin_end = 10;
        hbox.hexpand = true;

        // 1) ドラッグハンドル（アイコン）
        // var drag_icon = new Image.from_icon_name ("drag-indicator-symbolic");
        // drag_icon.tooltip_text = "ドラッグで並び替え";
        // edit_mode に連動して可視/不可視
        // ui_state.bind_property ("edit-mode", drag_icon, "visible",
        //                         BindingFlags.SYNC_CREATE);

        // 2) タイトル＋説明（縦）
        var vbox = new Box (Orientation.VERTICAL, 2);
        vbox.hexpand = true;
        var title = new Label ("") { xalign = 0.0f };
        title.add_css_class ("title-3");
        var url  = new Label ("") { xalign = 0.0f };
        url.add_css_class ("dim-label");
        url.wrap = true; url.ellipsize = Pango.EllipsizeMode.END;
        vbox.append (title);
        vbox.append (url);

        // 3) 削除ボタン（行末）
        var del = new Button.from_icon_name ("user-trash-symbolic");
        del.tooltip_text = _("Remove");
        ui_state.bind_property ("edit-mode", del, "visible",
                                BindingFlags.SYNC_CREATE);

        // 行の並び
        // hbox.append (drag_icon);
        hbox.append (vbox);
        hbox.append (del);

        // ListItem にセット
        li.set_child (hbox);

        // 行全体にクリックジェスチャを付与
        var click = new Gtk.GestureClick ();
        click.released.connect ((n_press, x, y) => {
            if (n_press == 1) {
                // 現在の行位置を使ってアクティベーション発火
                bd_list_boards.activate (li.position);
            }
        });
        vbox.add_controller (click);

        // listItemWidgetを取得
        var row_widget = (Gtk.Widget) hbox.get_parent ();

        // --- 削除ボタンで行を削除 ---
        del.clicked.connect (() => {
            uint pos = li.position;
            if (pos >= 0 && pos < (int) store.get_n_items ()) {
                try {
                    Db.DB db = new Db.DB();
                    Sqlite.Statement st;
                    string sql = """
                        DELETE from bbslist where
                        url = ?1
                    """;

                    var bi = (BoardsItem) li.item;
                    var deleteurl = bi.url;

                    db.exec (sql, {deleteurl});
                } catch (Error e) {
                    show_error_toast (e.message);
                    print(e.message);
                }

                bbslist();
            }

        });
    }

    // --- データのバインド ---
    private void on_bind (Gtk.SignalListItemFactory f, GLib.Object obj) {
        var li = (Gtk.ListItem) obj;
        var item = (BoardsItem) li.item;

        var hbox = (Box) li.get_child ();          // [0]=vbox, [1]=del
        var vbox = (Box) hbox.get_first_child ();  // ← ここが vbox
        var title = (Label) vbox.get_first_child ();
        var url   = (Label) title.get_next_sibling ();

        title.label = item.title;
        url.label  = item.url;
    }

    // 追加ウィンドウポップアップ
    private void on_button_add() {
        var window = this.get_ancestor (typeof (Gtk.Window)) as Gtk.Window;
        var popup = new AddBoardWindow (window, g_app);
        popup.submitted.connect ((text) => {
            this.add_bbs_list (text);
        });
        popup.present ();
    }

    private void on_button_hist() {
        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        nav.push(new thread_hist ());
    }

    // リストに追加
    private async void add_bbs_list (string url) {
        // URLからタイトルを取得
        var client = new FiveCh.Client ();
        string name;
        try {
            name = yield client.fetch_board_title_from_url_async (url);
            if (name == null) {
                show_error_toast ("Invalid URL");
                return;
            }
        } catch {
            show_error_toast ("Invalid Error");
            return;
        }

        // DB更新
        try {
            Db.DB db = new Db.DB();
            string sql = """
                INSERT INTO bbslist (url, name)
                VALUES (?1, ?2)
            """;

            db.exec (sql, {url, name});

        } catch {
            show_error_toast ("Duplicate URL");
            return;
        }

        bbslist();

    }

    // ListStore からアイテムのインデックスを探す簡易ヘルパ
    // private int index_of (BoardsItem it) {
    //     int n = (int) store.get_n_items ();
    //     for (int i = 0; i < n; i++) {
    //         if (store.get_item (i) == it) return i;
    //     }
    //     return -1;
    // }

    private void on_row_activated (uint pos) {
        var item = (BoardsItem) store.get_item ((int)pos);

        // 次の画面へ遷移
        var nav = this.get_ancestor (typeof (Adw.NavigationView)) as Adw.NavigationView;
        if (nav == null) {
            return;
        }
        nav.push(new ThreadsView (item.url, item.title));
    }

    // 掲示板一覧更新
    private void bbslist () {
        // dbファイル読み込み、保存しているスレッドを取得,
        Db.DB db = new Db.DB();

        var rows = db.query ("""
            SELECT url, name
              FROM bbslist
             ORDER BY name asc
        """, {});

        store.remove_all ();
        foreach (var r in rows) {
            var n = Db.BbsList.from_row (r);
            store.append (new BoardsItem (
                n.name,
                n.url
            ));
        }
    }

    // エラー表示
    public void show_error_toast (string message) {
        var toast = this.get_ancestor (typeof (Adw.ToastOverlay)) as Adw.ToastOverlay;
        if (toast == null) {
            return;
        }
        var t = new Adw.Toast (message);
        t.set_timeout (5); // 秒

        toast.add_toast (t);
    }

    // DBの掃除
    public async void clean_data () {
        try {
            Db.DB db = new Db.DB();

            var sql = """
                WITH to_keep AS (
                  SELECT rowid
                  FROM tempwrite
                  ORDER BY last_touch_date DESC
                  LIMIT 1000
                )
                DELETE FROM tempwrite
                WHERE rowid NOT IN (SELECT rowid FROM to_keep)
            """;
            db.exec (sql, {});

            sql = """
                WITH to_keep AS (
                  SELECT rowid
                  FROM threadlist
                  ORDER BY last_touch_date DESC
                  LIMIT 1000
                )
                DELETE FROM threadlist
                WHERE rowid NOT IN (SELECT rowid FROM to_keep)
            """;
            db.exec (sql, {});

        } catch {}
    }
}

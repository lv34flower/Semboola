/* ress.vala
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
 *w
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gtk;
using GLib;
using Gdk;
using Adw;
using FiveCh;

[GtkTemplate (ui = "/jp/lv34/Semboola/ress.ui")]
public class RessView : Adw.NavigationPage {

    private string url;
    private string name;

    Semboola.Window win;

    private DatLoader loader;

    private GLib.ListStore store = new GLib.ListStore (typeof (ResRow.ResItem));

    // 初期化フラグ
    private bool initialized = false;

    [GtkChild]
    unowned Gtk.ListBox listview;

    public RessView (string url, string name) {
        // Object(
        //     title:name
        // );
        //
        this.url = url;
        this.name = name;

        loader = new DatLoader ();

        // var selection = new Gtk.SingleSelection (store);
        // selection.autoselect = false;
        // selection.can_unselect = true;

        // var factory = new Gtk.SignalListItemFactory ();
        // factory.setup.connect (on_factory_setup);
        // factory.bind.connect (on_factory_bind);

        // listview.model = selection;
        // listview.factory = factory;


        // bind_model 使用
        listview.bind_model (store, (obj) => {
            var post = (ResRow.ResItem) obj;

            var row_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            row_box.margin_top = 6;
            row_box.margin_bottom = 6;
            row_box.margin_start = 8;
            row_box.margin_end = 16;

            var header = new Gtk.Label (null);
            header.use_markup = true;
            header.xalign = 0.0f;
            header.wrap = true;
            header.wrap_mode = Pango.WrapMode.WORD_CHAR;
            //header.ellipsize = Pango.EllipsizeMode.END;

            var body = new ClickableLabel ();

            // ここで span イベント接続（ListView版と同じノリ）
            body.span_left_clicked.connect ((span) => {
                on_span_left_clicked (post, span);
            });
            body.span_right_clicked.connect ((span, x, y) => {
                on_span_right_clicked (post, span, x, y, body);
            });

            // ★ここが抜けてた：中身を row_box に入れる
            row_box.append (header);
            row_box.append (body);

            // 中身セット
            set_post_widgets (post, header, body);

            var row = new Gtk.ListBoxRow ();
            row.set_child (row_box);
            return row;
        });
        // NavigationView に push されて画面に出る直前〜直後に呼ばれる
        this.shown.connect (() => {
            win = this.get_root() as Semboola.Window;
            init_load.begin ();
        });

    }

    static construct {
        typeof (ResRow).ensure ();

        // 行がアクティブ化されたとき（pos は行番号）
        // listview.activate.connect (on_row_activated);
    }

    private void set_post_widgets (ResRow.ResItem post, Gtk.Label header, ClickableLabel body) {
        string safe_name = Markup.escape_text (post.name);
        string safe_date = Markup.escape_text (post.date);
        string id_part = (post.id != "")
            ? @" <span foreground='#c03030'>ID:$(Markup.escape_text (post.id))</span>"
            : "";

        header.set_markup (@"<b>$(post.index)</b> $safe_name  $safe_date$id_part");

        var spans = SpanBuilder.build (post.body);
        body.set_spans (spans);
    }

    // 最初の読み込み
    private async void init_load () {
        if (initialized) {
            return;
        }

        yield reload();

        initialized = true;
    }

    private async void reload () {
        this.title=_("Loading...");
        try {
            var cancellable = new Cancellable ();
            var posts = yield loader.load_from_url_async (url, cancellable);

            store.remove_all ();
            foreach (var p in posts) {
                store.append (p);
            }
        } catch (Error e) {

        } finally {
             this.title=name;
        }
    }

    // -------- Spanクリック時の動作 --------

    private void on_span_left_clicked (ResRow.ResItem post, Span span) {
        switch (span.type) {
        case SpanType.REPLY:
            if (span.payload != null) {
                uint target;
                try {
                    target = (uint) int.parse (span.payload);
                } catch (Error e) {
                    return;
                }
                scroll_to_post (target);
            }
            break;
        case SpanType.URL:
            if (span.payload != null) {
                try {
                    var launcher = new Gtk.UriLauncher (span.payload);
                    launcher.launch.begin (null, null);
                } catch (Error e) {
                    // 失敗時は無視
                }
            }
            break;
        default:
            break;
        }
    }

    private void on_span_right_clicked (ResRow.ResItem post, Span span, double x, double y, Gtk.Widget widget) {
        switch (span.type) {
        case SpanType.REPLY:
            if (span.payload != null) {
                try {
                    uint target = (uint) int.parse (span.payload);
                    scroll_to_post (target);
                } catch (Error e) {}
            }
            break;
        case SpanType.URL:
            if (span.payload != null) {
                try {
                    var launcher = new Gtk.UriLauncher (span.payload);
                    Gtk.Window? parent = this.get_root () as Gtk.Window;
                    launcher.launch.begin (parent, null);
                } catch (Error e) {}
            }
            break;
        default:
            break;
        }
    }


    private void scroll_to_post (uint index) {
        // ResRow.ResItem.index == 表示番号として検索
        // for (uint i = 0; i < store.get_n_items (); i++) {
        //     var p = (ResRow.ResItem) store.get_item (i);
        //     if (p.index == index) {
        //         listview.scroll_to (i, Gtk.ListScrollFlags.NONE, null);
        //         break;
        //     }
        // }
    }

    [GtkCallback]
    private void on_reload_click () {
        reload.begin ();
    }

}

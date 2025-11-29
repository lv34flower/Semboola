using Gtk;
using Gdk;


namespace common {
    // クリップボードセット
    void copy_to_clipboard (string text) {
        var display = Display.get_default ();
        if (display == null) {
            warning ("No display");
            return;
        }

        var clipboard = display.get_clipboard ();

        clipboard.set_text (text);
    }

    async void open_url (string url, Adw.NavigationView nav) {
        try {
            var token_rx = FiveCh.SpanBuilder.get_token_regex ();

            MatchInfo mi;
            int last = 0;

            token_rx.match (url, 0, out mi);
            while (mi.matches ()) {
                int start, end;
                mi.fetch_pos (0, out start, out end);

                var full = mi.fetch (0);
                var g_reply = mi.fetch (1);
                var g_threadurl = mi.fetch (2);
                var g_boardurl = mi.fetch(3);
                var g_url = mi.fetch (4);
                var g_id = mi.fetch (5);

                if (g_reply != null && g_reply.length > 0) {

                } else if (g_url != null && g_url.length > 0) {

                } else if (g_id != null && g_id.length > 0){

                } else if (g_threadurl != null && g_threadurl.length > 0 ) {
                    nav.push(new RessView (url, "", 0));
                    return;
                } else if (g_boardurl != null && g_boardurl.length > 0 ) {
                    var client = new FiveCh.Client ();
                    string new_title = "";
                    new_title = yield client.fetch_board_title_from_url_async (url);
                    if (new_title == null) {
                        throw new IOError.FAILED ("");
                    }
                    nav.push(new ThreadsView (url, new_title));
                    return;
                } else {
                }

                throw new IOError.FAILED("");//無意味error
            }
        } catch {
            // 普通に開く
            message (url);
            var launcher = new Gtk.UriLauncher (url);
            launcher.launch.begin (null, null);
        }
    }

    // DBの掃除
    async void clean_data () {
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

            sql = """
                WITH to_keep AS (
                  SELECT rowid
                  FROM posthist
                  ORDER BY last_touch_date DESC
                  LIMIT 1000
                )
                DELETE FROM posthist
                WHERE rowid NOT IN (SELECT rowid FROM to_keep)
            """;
            db.exec (sql, {});

        } catch {}
    }

    // 板をリストに追加
    async void add_bbs_list (string url, Semboola.Window win) {
        // URLからタイトルを取得
        var client = new FiveCh.Client ();
        string name;
        try {
            name = yield client.fetch_board_title_from_url_async (url);
            if (name == null) {
                win.show_error_toast ("Invalid URL");
                return;
            }
        } catch {
            win.show_error_toast ("Invalid Error");
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
            win.show_error_toast ("Duplicate URL");
            return;
        }

    }

    // 板を削除
    async void remove_bbs_list (string url, Semboola.Window win) {
        try {
            Db.DB db = new Db.DB();
            Sqlite.Statement st;
            string sql = """
                DELETE from bbslist where
                url = ?1
            """;

            db.exec (sql, {url});
        } catch (Error e) {
            win.show_error_toast (e.message);
        }
    }

}

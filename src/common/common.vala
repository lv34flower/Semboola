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

                last = end;
                mi.next ();
            }
        } catch {
            // 普通に開く
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

        } catch {}
    }

}

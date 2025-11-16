using GLib;
using Gee;
using Sqlite;

namespace Db {

    // SQLite3用Helper
    public class DB : Object {
        public Sqlite.Database db;
        string errmsg;

        public DB () throws Error {
            db = getInstance ();
        }

        // 影響行数がほしい UPDATE/INSERT/DELETE 用
        // public int exec (string sql, string[] params = {}) throws Error {
        //     Sqlite.Statement st;
        //     int rc = db.prepare_v2 (sql, -1, out st, null);
        //     if (rc != Sqlite.OK) throw new Error.FAILED ("prepare: %s", Sqlite.errstr (rc));
        //     bind_all (st, params);
        //     rc = st.step ();
        //     int changes = (rc == Sqlite.DONE) ? db.changes () : 0;
        //     st.finalize ();
        //     if (rc != Sqlite.DONE) throw new Error.FAILED ("step: %s", Sqlite.errstr (rc));
        //     return changes;
        // }

        // 1行取得（なければ null）
        // public HashMap<string,string>? query_one (string sql, string[] params = {}) throws Error {
        //     var rows = query (sql, params, 1);
        //     return rows.size > 0 ? rows[0] : null;
        // }

        // 複数行取得（列名→文字列 の辞書で返す。必要なら型変換は呼び出し側で）
        public ArrayList<HashMap<string,string>> query (string sql, string[] params = {}, int limit = int.MAX) throws Error {
            var outlist = new ArrayList<HashMap<string,string>> ();
            Sqlite.Statement st;

            int rc = db.prepare_v2 (sql, -1, out st, null);
            if (rc != Sqlite.OK) throw new IOError.FAILED ("prepare: %s", db.errmsg ());
            bind_all (st, params);

            int ncols = st.column_count ();
            string[] names = {};
            for (int i = 0; i < ncols; i++) names += st.column_name (i);

            while ((rc = st.step ()) == Sqlite.ROW) {
                var row = new HashMap<string,string> ();
                for (int i = 0; i < ncols; i++) {
                    unowned string? v = st.column_text (i);
                    row.set (names[i], (v != null) ? (string) v : "");
                }
                outlist.add (row);
                if (outlist.size >= limit) break;
            }
            st.reset ();
            if (rc != Sqlite.DONE && rc != Sqlite.ROW)
                throw new IOError.FAILED ("step: %d", rc);
            return outlist;
        }

        // 直近のROWID（単純INSERTのID取得に）
        public int64 last_insert_rowid () {
            return db.last_insert_rowid ();
        }

        private void bind_all (Sqlite.Statement st, string[] params) {
            for (int i = 0; i < params.length; i++) {
                st.bind_text (i + 1, params[i]); // シンプルに全部 TEXT bind（SQLite の型親和性に任せる）
            }
        }
    }

    public class ThreadList : Object {
        public string board_url;
        public string bbs_id;
        public string thread_id;
        public int current_res_count;
        public int favorite;
        public uint64 last_touch_date;

        public static ThreadList from_row (HashMap<string,string> r) {
            var n = new ThreadList ();
            n.board_url  = r["board_url"];
            n.bbs_id = r["bbs_id"];
            n.thread_id = r["thread_id"];
            n.current_res_count = r["current_res_count"].to_int ();
            n.favorite = r["favorite"].to_int ();
            n.last_touch_date = r["last_touch_date"].to_uint64 ();
            return n;
        }
    }

    public class BbsList : Object {
        public string url;
        public string name;

        public static BbsList from_row (HashMap<string,string> r) {
            var n = new BbsList ();
            n.url  = r["url"];
            n.name = r["name"];
            return n;
        }
    }

    /* SQLiteのインスタンスを返します。
     * ディレクトリがなければ作成します。ファイルが存在しない場合は空のDBを作成します。
     *
     *  */
    Sqlite.Database getInstance() {
        string data_dir = Environment.get_user_data_dir();

        File dir = File.new_for_path (data_dir);

        if (!dir.query_exists ()) {
            dir.make_directory_with_parents ();
        }

        string db_path = Path.build_filename (data_dir, "data.db");

        Sqlite.Database db;
        int rc = Sqlite.Database.open (db_path, out db);
        if (rc != Sqlite.OK) {
            stderr.printf ("DB open error:(%d)\n", rc);

            throw new IOError.FAILED("DB open error");
        }

        return db;
    }
}

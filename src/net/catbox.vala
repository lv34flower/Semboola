using GLib;
using Soup;

public errordomain CatboxError {
    HTTP_ERROR,
    API_ERROR
}

public class CatboxClient : Object {

    private Soup.Session session;

    public CatboxClient () {
        session = new Soup.Session ();
        session.user_agent = "SemboolaCatboxUploader/0.1 (GTK4; libsoup3)";
    }

    private async string upload_file_async (
        File file,
        Cancellable? cancellable = null
    ) throws Error {
        // ファイル読み込み
        string? etag = null;
        Bytes body = file.load_bytes (cancellable, out etag);

        // ファイル名 / MIME
        string filename = file.get_basename () ?? "upload.bin";
        string content_type = "application/octet-stream";
        try {
            var info = file.query_info ("standard::content-type", FileQueryInfoFlags.NONE, cancellable);
            var ct = info.get_content_type ();
            if (ct != null && ct.length > 0) content_type = ct;
        } catch (Error e) {
        }

        // Catbox API: reqtype=fileupload, (optional) userhash, fileToUpload :contentReference[oaicite:2]{index=2}
        var mp = new Soup.Multipart ("multipart/form-data");
        mp.append_form_string ("reqtype", "fileupload");

        mp.append_form_file ("fileToUpload", filename, content_type, body);

        var msg = new Soup.Message.from_multipart ("https://catbox.moe/user/api.php", mp);
        msg.request_headers.replace ("Accept", "text/plain");

        Bytes resp = yield session.send_and_read_async (msg, Priority.DEFAULT, cancellable);

        if (msg.status_code < 200 || msg.status_code >= 300) {
            throw new CatboxError.HTTP_ERROR ("HTTP %u".printf (msg.status_code));
        }

        // Catbox はプレーンテキストでURLが返る（基本）:contentReference[oaicite:3]{index=3}
        string text = ((string) resp.get_data ()).strip ();

        // 検証
        if (text.has_prefix ("http://") || text.has_prefix ("https://")) {
            return text;
        }

        throw new CatboxError.API_ERROR ("Catbox response: %s".printf (text));
    }

    public async string upload (File file) throws Error {
        // 同一ファイルが上がってないか
        Db.DB db = new Db.DB ();
        string sql = """
            SELECT *
              FROM uploadimg
             WHERE local_path = ?1
        """;
        var rows = db.query (sql, { file.get_path () ?? file.get_uri () });
        foreach (var r in rows) {
            var url = r["url"];
            return url;
        }

        string url;
        try {
            url = yield upload_file_async (file);
        } catch (Error e) {
            // 呼び出し側が Toast 等で出せるように、ここでは空返しせず例外扱いにしたいなら throw してください。
            warning ("%s", e.message);
            return "";
        }

        sql = """
            INSERT INTO uploadimg (url, last_touch_date, local_path, deletehash)
            VALUES (?1, ?2, ?3, ?4)
        """;
        db.exec (sql, {
            url,
            new DateTime.now_utc ().to_unix ().to_string (),
            file.get_path () ?? file.get_uri (),
            ""
        });

        return url;
    }
}


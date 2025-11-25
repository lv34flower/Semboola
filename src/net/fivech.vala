using GLib;
using Soup;
using Posix;

namespace FiveCh {

    // アプリケーション内共通の変数
    public string cookie;  // cookie.txtのパス
    string ua;  // UAのパス
    string ua_text = null; // uaの内容
    Session g_session;
    CookieJar g_cookiejar;
    // ----------------------------

    /** Represents one line in subject.txt */
    public class SubjectEntry : Object {
        public string threadkey { get; construct; }
        public string title     { get; construct; }
        public int    count     { get; construct; }
        public string dat_url   { get; construct; }
        public string raw_line  { get; construct; }

        public SubjectEntry (string threadkey, string title, int count, string dat_url, string raw_line) {
            Object (threadkey: threadkey, title: title, count: count, dat_url: dat_url, raw_line: raw_line);
        }

        // --- Added: time & ikioi helpers ---
        /** スレ作成UNIX秒（threadkeyをそのまま数値化。失敗時は0） */
        public int64 creation_epoch {
            get {
                try { return int64.parse (threadkey); } catch (Error e) { return 0; }
            }
        }

        /** Localの作成日時 */
        public DateTime creation_datetime_local () {
            return new DateTime.from_unix_local (creation_epoch);
        }

        /** 現在時刻基準の勢い（レス/時）。(count ÷ 経過時間[時]) */
        public double ikioi_per_hour_now () {
            int64 now = (int64) (GLib.get_real_time () / 1000000);
            return ikioi_per_hour_at (now);
        }

        /** 指定UNIX秒時点の勢い（レス/時）。時間差が0以下なら count を返す */
        public double ikioi_per_hour_at (int64 now_epoch) {
            double hours = ((double) (now_epoch - creation_epoch)) / 3600.0;
            if (hours <= 0.0) return (double) count;
            return ((double) count) / hours;
        }
    }

    /** Chunk of DAT fetch with optional next offset */
    public class DatChunk : Object {
        public string text          { get; construct; }  // decoded UTF-8
        public int64  next_from_byte { get; construct; } // suggested next Range offset
        public bool   partial        { get; construct; } // true if 206

        public DatChunk (string text, int64 next_from_byte, bool partial) {
            Object (text: text, next_from_byte: next_from_byte, partial: partial);
        }
    }

    /** Options for posting */
    public class PostOptions : Object {
        /**
         * Target charset for x-www-form-urlencoded percent-encoding.
         * Typical 2ch互換は CP932。UTF-8対応板なら "UTF-8" を指定。
         */
        public string charset { get; set; default = "CP932//IGNORE"; }
        /** Optional extra headers (e.g., Referer). */
        public HashTable<string,string>? extra_headers { get; set; }
        /** Override UA only for this request. */
        public string? user_agent_override { get; set; }
        /** Submit button label (server side may expect something). */
        public string submit_label { get; set; default = "書き込む"; }
    }

    /** Per-board settings holder (minimal) */
    public class Board : Object {
        public string site_base_url { get; construct; } // e.g. https://example.com/test/ read as site base
        public string board_key     { get; construct; } // e.g. "linux"
        public string user_agent    { get; set; default = default_browser_ua (); }

        public Board (string site_base_url, string board_key) {
            Object (site_base_url: site_base_url, board_key: board_key);
        }

        public string subject_url () {
            return ensure_board_base () + "subject.txt";
        }
        public string setting_url () {
            return ensure_board_base () + "SETTING.TXT";
        }
        public string dat_url (string threadkey) {
            return ensure_board_base () + "dat/" + threadkey + ".dat";
        }
        public string bbs_cgi_url () { // posting endpoint
            // Standard: https://{host}/test/bbs.cgi
            return ensure_site_base () + "test/bbs.cgi";
        }
        private string ensure_site_base () {
            string b = site_base_url;
            if (!b.has_suffix ("/")) b += "/";
            return b;
        }
        public string ensure_board_base () {
            // Construct https://{host}/{board_key}/
            var board_base = ensure_site_base () + board_key + "/";
            return board_base;
        }

        // Extract board key from typical 5ch-like URLs
        // Supported forms:
        //  - https://host/test/read.cgi/<board>/<key>/...
        //  - https://host/<board>/subject.txt
        //  - https://host/<board>/dat/<key>.dat
        //  - https://host/<board>/SETTING.TXT
        // Fallback: first path segment after host
        public static string? guess_board_key_from_url (string url) {
            try {
                MatchInfo m;
                // read.cgi
                var r1 = new GLib.Regex ("/test/read\\.cgi/([^/]+)/", GLib.RegexCompileFlags.CASELESS);
                if (r1.match (url, 0, out m)) return m.fetch (1);
                // subject.txt
                var r2 = new GLib.Regex ("://[^/]+/([^/]+)/subject\\.txt", GLib.RegexCompileFlags.CASELESS);
                if (r2.match (url, 0, out m)) return m.fetch (1);
                // dat/
                var r3 = new GLib.Regex ("://[^/]+/([^/]+)/dat/", GLib.RegexCompileFlags.CASELESS);
                if (r3.match (url, 0, out m)) return m.fetch (1);
                // SETTING.TXT
                var r4 = new GLib.Regex ("://[^/]+/([^/]+)/SETTING\\.TXT", GLib.RegexCompileFlags.CASELESS);
                if (r4.match (url, 0, out m)) return m.fetch (1);
                // Fallback: first segment
                var r5 = new GLib.Regex ("://[^/]+/([^/]+)/", GLib.RegexCompileFlags.CASELESS);
                if (r5.match (url, 0, out m)) return m.fetch (1);
            } catch (Error e) { }
            return null;
        }

        // Extract scheme+host (origin) ending with '/'
        public static string? guess_site_base_from_url (string url) {
            try {
                MatchInfo m;
                var r = new GLib.Regex ("^([a-zA-Z][a-zA-Z0-9+.-]*://[^/]+)/", GLib.RegexCompileFlags.CASELESS);
                if (r.match (url, 0, out m)) return m.fetch (1) + "/";
            } catch (Error e) { }
            return null;
        }
    }

    /** Main client wrapping libsoup3 */
    public class Client : Object {

        // 投稿の結果
        public enum PostPageKind {
            OK,
            ERROR,
            CONFIRM
        }

        // 投稿の結果+メッセージ
        public class PostResult : Object {
            public PostPageKind kind                      { get; construct; }
            public string       html                      { get; construct; }
            public string?      title                     { get; construct; }
            public string?      tag_2ch                   { get; construct; }
            public string?      message                   { get; construct; }
            public string?      error_message             { get; construct; }
            public string?      confirm_message           { get; construct; }
            public HashTable<string,string>? confirm_form { get; construct; }

            public PostResult (PostPageKind kind,
                               string html,
                               string? title = null,
                               string? tag_2ch = null,
                               string? message = null,
                               string? error_message = null,
                               string? confirm_message = null,
                               HashTable<string,string>? confirm_form = null) {
                Object (kind: kind,
                        html: html,
                        title: title,
                        tag_2ch: tag_2ch,
                        message: message,
                        error_message: error_message,
                        confirm_message: confirm_message,
                        confirm_form: confirm_form);
            }
        }


        public Session session { get; private set; }
        public CookieJar cookiejar { get; private set; }

        public Client () {
            session = g_session;
            session.user_agent = default_browser_ua ();
            cookiejar = g_cookiejar;
            session.add_feature (cookiejar);

            // Follow redirects automatically (default true). Compression is automatic.
        }

        // -------------- SUBJECT.TXT --------------
        public async List<SubjectEntry> fetch_subject_async (Board board, Cancellable? cancel = null) throws Error {
            var url = board.subject_url ();
            var bytes = yield send_get_bytes_async (url, board.user_agent, null, cancel);
            string __enc_tmp; var text = decode_text_guess_japanese (bytes, out __enc_tmp);
            text = decode_html_entities (text);
            return parse_subject (text, board);
        }

        // -------------- SETTING.TXT --------------
        public async HashTable<string,string> fetch_setting_async (Board board, Cancellable? cancel = null) throws Error {
            var url = board.setting_url ();
            var bytes = yield send_get_bytes_async (url, board.user_agent, null, cancel);
            string __enc_tmp;
            var text = decode_text_guess_japanese (bytes, out __enc_tmp);
            text = decode_html_entities (text);
            var map = new HashTable<string,string> (str_hash, str_equal);
            foreach (var line in text.split("\n")) {
                if (line.strip ().length == 0) continue;
                var idx = line.index_of ("=");
                if (idx > 0) {
                    var k = line.substring (0, idx).strip ();
                    var v = line.substring (idx + 1).strip ();
                    map[k] = v;
                }
            }
            return map;
        }

        // -------------- DAT (Range) --------------
        /**
         * Fetch thread DAT. If from_byte >= 0, sends Range: bytes=from- to tail-read.
         * Returns DatChunk with decoded UTF-8 text and suggested next offset.
         */
        public async DatChunk fetch_dat_async (Board board, string threadkey, int64 from_byte = -1, Cancellable? cancel = null) throws Error {
            var url = board.dat_url (threadkey);
            var extra = new HashTable<string,string> (str_hash, str_equal);
            if (from_byte >= 0) extra["Range"] = @"bytes=$(from_byte)-";

            var response = yield send_get_full_async (url, board.user_agent, extra, cancel);

            bool partial = (response.status == 206);
            Bytes body = response.body;
            string __enc_dat; string text = decode_text_guess_japanese (body, out __enc_dat);

            // Compute next offset from Content-Range or Content-Length
            int64 next_from = -1;
            string? cr = response.headers.get_one ("Content-Range");
            if (cr != null) {
                // e.g. bytes 123-999/1000
                try {
                    var parts = cr.split (" ");
                    if (parts.length == 2) {
                        var span_total = parts[1].split ("/");
                        var span = span_total[0];
                        var xy = span.split ("-");
                        int64 start = int64.parse (xy[0]);
                        int64 end   = int64.parse (xy[1]);
                        next_from = end + 1; // next byte
                    }
                } catch (Error e) { /* ignore */ }
            }
            if (next_from < 0) {
                // Fallback: accumulate using provided from_byte + body size
                if (from_byte >= 0) next_from = from_byte + (int64) body.get_size ();
            }
            return new DatChunk (text, next_from, partial);
        }

        // -------------- POST /test/bbs.cgi --------------
        /**
         * Post reply or create new thread.
         * Required fields: bbs, key (omit for new), MESSAGE; FROM/mail optional; subject for new thread.
         * Many servers expect CP932 (MS932); set options.charset = "UTF-8" if board supports UTF-8.
         */

        public async PostResult post_with_analysis_async (Board board,
                                                          string bbs,
                                                          string? key,
                                                          string message,
                                                          string from = "",
                                                          string mail = "",
                                                          string? subject = null,
                                                          PostOptions? options = null,
                                                          Cancellable? cancel = null) throws Error {
            PostOptions opts = options ?? new PostOptions ();

            var form = new HashTable<string,string> (str_hash, str_equal);
            if (subject != null) form["subject"] = encode_html_entities(subject);
            form["FROM"]    = encode_html_entities(from);
            form["mail"]    = encode_html_entities(mail);
            form["MESSAGE"] = encode_html_entities(message);
            if (key != null) form["key"] = key;
            form["bbs"]     = bbs;
            form["time"]    = ((int64) (get_real_time ()/1000000)).to_string ();
            form["submit"]  = opts.submit_label;

            opts.extra_headers = opts.extra_headers ?? new HashTable<string,string> (str_hash, str_equal);
            if (subject == null)
                opts.extra_headers["Referer"] = board.dat_url (key);
            else
                opts.extra_headers["Referer"] = board.ensure_board_base (); // スレ立てのリファラは板のURL

            opts.extra_headers["Origin"] = board.site_base_url;

            string html = yield post_once_async (board, form, opts, cancel);

            // HTML→PostResult
            return analyze_post_html (html);
        }

        private async string post_once_async (Board board,
                                              HashTable<string,string> form,
                                              PostOptions opts,
                                              Cancellable? cancel) throws Error {
            string encoded = urlencode_form (form, opts.charset);

            var msg = new Message ("POST", board.bbs_cgi_url ());

            var ua = opts.user_agent_override ?? board.user_agent;
            msg.request_headers.replace ("User-Agent", ua);
            msg.request_headers.replace ("Content-Type", "application/x-www-form-urlencoded");
            if (opts.extra_headers != null) {
                foreach (var k in opts.extra_headers.get_keys ()) {
                    var v = opts.extra_headers[k];
                    msg.request_headers.replace (k, v);
                }
            }

            var bytes = bytes_from_string_ascii (encoded);
            msg.set_request_body_from_bytes ("application/x-www-form-urlencoded", bytes);

            var resp_bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, cancel);

            string __enc_post;
            string text = decode_text_guess_japanese (resp_bytes, out __enc_post);

            var status = msg.get_status ();
            if (!(status == 200 || status == 301 || status == 302)) {
                throw new IOError.FAILED ("POST failed: %u — %s\n%s"
                    .printf ((uint) status, msg.get_reason_phrase (), text));
            }
            return text;
        }

        // HTML から ERROR: ～ を1行抜き出して返す。なければ null。
        private static string? extract_error_message (string html) {
            try {
                // <br> やタグをいったんざっくり落としてから探す
                string plain = strip_tags (html);
                plain = plain.replace ("<br>", "\n").replace ("<br />", "\n").replace ("<br/>", "\n");

                MatchInfo mi;
                var rx = new GLib.Regex ("ERROR[:：].*", GLib.RegexCompileFlags.CASELESS);
                if (rx.match (plain, 0, out mi)) {
                    var line = mi.fetch (0);
                    return line.strip ();
                }
            } catch (Error e) {
            }
            return null;
        }

        // attr_name="..." / attr_name='...' を抜く簡易ヘルパ
        private static string? extract_attr (string tag, string attr_name) {
            try {
                MatchInfo mi;
                var rx1 = new GLib.Regex ("\\b%s\\s*=\\s*'([^']*)'".printf (attr_name),
                                          GLib.RegexCompileFlags.CASELESS);
                if (rx1.match (tag, 0, out mi))
                    return mi.fetch (1);

                var rx2 = new GLib.Regex ("\\b%s\\s*=\\s*'([^']*)'".printf (attr_name),
                                          GLib.RegexCompileFlags.CASELESS);
                if (rx2.match (tag, 0, out mi))
                    return mi.fetch (1);
            } catch (Error e) {
            }
            return null;
        }



        public static PostResult analyze_post_html (string html) {
            string title = "";
            string tag_2ch = "";
            string msg = "";
            string conf = "";
            string? errmsg = null;

            try {
                MatchInfo mi;

                // <title>...</title>
                var rx_title = new GLib.Regex (".*<title>([^<]*)</title>.*",
                                               GLib.RegexCompileFlags.DOTALL | GLib.RegexCompileFlags.CASELESS);
                if (rx_title.match (html, 0, out mi)) {
                    title = mi.fetch (1).strip ();
                }

                // 2ch_X: 〜 -->
                var rx_tag = new GLib.Regex (".*2ch_X:([^\\-]*)\\-\\->.*",
                                             GLib.RegexCompileFlags.DOTALL);
                if (rx_tag.match (html, 0, out mi)) {
                    tag_2ch = mi.fetch (1).strip ();
                }

                // 一番内側の <b>〜</b> を雑に1つ拾う（JDimほど厳密ではない）
                var rx_b = new GLib.Regex ("<b>([^<]*)</b>",
                                           GLib.RegexCompileFlags.DOTALL | GLib.RegexCompileFlags.CASELESS);
                if (rx_b.match (html, 0, out mi)) {
                    errmsg = mi.fetch (1).strip ();
                }

                // まだ errmsg が空で tag_2ch に error があれば error --> ...</body> を拾ってみる
                if ((errmsg == null || errmsg == "") && tag_2ch.down ().contains ("error")) {
                    var rx_err2 = new GLib.Regex ("error +-->(.*)</body>",
                                                  GLib.RegexCompileFlags.DOTALL | GLib.RegexCompileFlags.CASELESS);
                    if (rx_err2.match (html, 0, out mi)) {
                        errmsg = mi.fetch (1).strip ();
                    }
                }

                // さらに title に error があれば <h4>..</h4> を見る
                if ((errmsg == null || errmsg == "") && title.down ().contains ("error")) {
                    var rx_h4 = new GLib.Regex ("<h4>(.*)</h4>",
                                                GLib.RegexCompileFlags.DOTALL | GLib.RegexCompileFlags.CASELESS);
                    if (rx_h4.match (html, 0, out mi)) {
                        errmsg = mi.fetch (1).strip ();
                    }
                }

                // フォント赤文字の「書き込み確認」文言
                var rx_conf = new GLib.Regex (".*<font size=\\+1 color=#FF0000>([^<]*)</font>.*",
                                              GLib.RegexCompileFlags.DOTALL);
                if (rx_conf.match (html, 0, out mi)) {
                    conf = mi.fetch (1).strip ();
                }

                // 本文メッセージ（JDimの </ul>.*<b>..</b> に近い場所を雑に拾う）
                var rx_msg = new GLib.Regex (".*</ul>.*<b>(.*)</b>.*<form.*",
                                             GLib.RegexCompileFlags.DOTALL);
                if (rx_msg.match (html, 0, out mi)) {
                    msg = mi.fetch (1).strip ();
                }
            } catch (Error e) {
                // 解析失敗時はそのまま fall-through
            }

            // ERROR: プレーンテキストを優先的に拾う
            string? err2 = extract_error_message (html);
            if (err2 != null && err2 != "") {
                errmsg = err2;
            }

            bool has_error = (errmsg != null && errmsg != "");

            // 「書きこみました」 or 2ch_X に true → 成功扱い
            bool looks_success =
                (title.contains ("書きこみました") ||
                 tag_2ch.down ().contains ("true"));

            // 「書き込み確認」「cookie」など → 確認画面っぽい
            bool looks_confirm =
                title.contains ("書き込み確認") ||
                conf.contains ("書き込み確認") ||
                tag_2ch.down ().contains ("cookie");

            // 確認フォーム（必要なときだけパース）
            HashTable<string,string>? confirm_form = null;
            if (looks_confirm) {
                confirm_form = parse_confirm_form (html);
            }

            if (looks_confirm) {
                return new PostResult (PostPageKind.CONFIRM,
                                       html,
                                       title,
                                       tag_2ch,
                                       msg,
                                       errmsg,
                                       conf,
                                       confirm_form);
            }

            if (has_error && !looks_success) {
                return new PostResult (PostPageKind.ERROR,
                                       html,
                                       title,
                                       tag_2ch,
                                       msg,
                                       errmsg,
                                       conf,
                                       null);
            }

            // どちらでもなければOK扱い（細かい判定は必要に応じて増やす）
            return new PostResult (PostPageKind.OK,
                                   html,
                                   title,
                                   tag_2ch,
                                   msg,
                                   null,
                                   conf,
                                   null);
        }

        public static HashTable<string,string>? parse_confirm_form (string html) {
            try {
                MatchInfo mi;
                var form_rx = new GLib.Regex ("<form[^>]*>(.*?)</form>",
                                              GLib.RegexCompileFlags.DOTALL | GLib.RegexCompileFlags.CASELESS);
                if (!form_rx.match (html, 0, out mi))
                    return null;

                string form_html = mi.fetch (1);
                var map = new HashTable<string,string> (str_hash, str_equal);

                // input タグ群
                MatchInfo mi_input;
                var input_rx = new GLib.Regex ("<input[^>]+>",
                                               GLib.RegexCompileFlags.CASELESS);
                input_rx.match (form_html, 0, out mi_input);
                while (mi_input.matches ()) {
                    string tag = mi_input.fetch (0);

                    string? name  = extract_attr (tag, "name");
                    if (name == null || name == "") {
                        mi_input.next ();
                        continue;
                    }

                    string? type  = extract_attr (tag, "type");
                    string? value = extract_attr (tag, "value") ?? "";

                    string type_l = type != null ? type.down () : "";

                    if (type_l == "submit") {
                        // サーバ側が期待する submit ラベル
                        map["submit"] = value.length > 0 ? value : "書き込む";
                    } else {
                        map[name] = value;
                    }

                    mi_input.next ();
                }

                // textarea も拾う（MESSAGE など）
                MatchInfo mi_textarea;
                var ta_rx = new GLib.Regex ("<textarea[^>]*name\\s*=\\s*\"([^\"]*)\"[^>]*>(.*?)</textarea>",
                                            GLib.RegexCompileFlags.DOTALL | GLib.RegexCompileFlags.CASELESS);
                ta_rx.match (form_html, 0, out mi_textarea);
                while (mi_textarea.matches ()) {
                    string name = mi_textarea.fetch (1);
                    string val  = mi_textarea.fetch (2);
                    map[name] = decode_html_entities (val);
                    mi_textarea.next ();
                }

                if (map.size () == 0)
                    return null;

                return map;
            } catch (Error e) {
            }
            return null;
        }

        // From any 5ch-like URL, fetch board title (BBS_TITLE in SETTING.TXT).
        public async string? fetch_board_title_from_url_async (string url, Cancellable? cancel = null) throws Error {
            var key  = FiveCh.Board.guess_board_key_from_url (url);
            var site = FiveCh.Board.guess_site_base_from_url (url);
            if (key == null || site == null) return null;

            var board = new FiveCh.Board (site, key);
            var set = yield fetch_setting_async (board, cancel);

            string? title = null;
            if (set.contains ("BBS_TITLE")) title = set["BBS_TITLE"];
            else if (set.contains ("BBS_TITLE_PLAIN")) title = set["BBS_TITLE_PLAIN"];

            if (title != null) title = strip_tags (title);
            return title;
        }

        // very small & safe tag stripper
        private static string strip_tags (string s) {
            try {
                var rx = new GLib.Regex ("<[^>]+>");
                return rx.replace (s, -1, 0, "");
            } catch (Error e) { return s; }
        }

        // ----------------- Low-level helpers -----------------
        private class FullResponse : Object {
            public uint status { get; construct; }
            public Soup.MessageHeaders headers { get; construct; }
            public Bytes body { get; construct; }
            public FullResponse (uint status, Soup.MessageHeaders headers, Bytes body) {
                Object (status: status, headers: headers, body: body);
            }
        }

        private async Bytes send_get_bytes_async (string url,
                                                  string user_agent,
                                                  HashTable<string,string>? extra_headers,
                                                  Cancellable? cancel) throws Error {
            var resp = yield send_get_full_async (url, user_agent, extra_headers, cancel);
            if (!(resp.status == 200 || resp.status == 206)) {
                throw new IOError.FAILED ("GET %s failed: %u".printf (url, (uint) resp.status));
            }
            return resp.body;
        }

        private async FullResponse send_get_full_async (string url,
                                                        string user_agent,
                                                        HashTable<string,string>? extra_headers,
                                                        Cancellable? cancel) throws Error {
            var msg = new Message ("GET", url);
            msg.request_headers.replace ("User-Agent", user_agent);
            if (extra_headers != null) {
                foreach (var k in extra_headers.get_keys ()) {
                    var v = extra_headers[k];
                    msg.request_headers.replace (k, v);
                }
            }

            var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, cancel);
            return new FullResponse ((uint) msg.get_status (), msg.get_response_headers (), bytes);
        }

        // Decode text with Japanese encodings guess: prefer UTF-8, then CP932, Shift_JIS, EUC-JP, ISO-2022-JP
        public static string decode_text_guess_japanese (Bytes bytes, out string used_encoding) {
            size_t sz = bytes.get_size ();
            unowned uint8[] data = (uint8[]) bytes.get_data ();
            // Try UTF-8 first
            string raw = (string) data;
            if (raw.validate ((ssize_t) sz)) {
                used_encoding = "UTF-8";
                // len バイトだけをコピーして NUL 終端された string を作る
                // ※ GLib.strndup ではなく、string.ndup を使う
                string s = raw.ndup (sz);
                return s;
            }

            string[] encs = { "CP932", "Shift_JIS", "EUC-JP", "ISO-2022-JP" };
            foreach (var enc in encs) {
                try {
                    string converted = convert_bytes (data, sz, "UTF-8//IGNORE", enc);
                    used_encoding = enc;
                    return converted;
                } catch (Error e) { }
            }
            // Last resort: interpret as ISO-8859-1 and return as UTF-8 replacement
            used_encoding = "binary";
            return ((string) data).make_valid (); // replace invalid sequences
        }

        // Convert raw bytes from -> to using GLib.convert; bytes may be arbitrary (non-UTF-8)
        private static string convert_bytes (uint8[] inb, size_t in_len, string to_codeset, string from_codeset) throws Error {
            // GLib.convert works on (string), but we can safely cast because it uses raw bytes and length.
            unowned string raw = (string) inb;
            size_t br = 0; size_t bw = 0;
            // Vala binding: GLib.convert (string str, ssize_t len, string to, string from, out size_t bytes_read, out size_t bytes_written)
            string outstr = GLib.convert (raw, (long) in_len, to_codeset, from_codeset, out br, out bw);
            return outstr; // UTF-8 string when to_codeset == "UTF-8"
        }

        // Create GLib.Bytes from ASCII/UTF-8 string without trailing NUL
        private static GLib.Bytes bytes_from_string_ascii (string s) {
            uint8[] arr = new uint8[s.length];
            unowned uint8[] raw = (uint8[]) s.data;
            for (int i = 0; i < s.length; i++) arr[i] = (uint8) raw[i];
            return new GLib.Bytes (arr);
        }

        // application/x-www-form-urlencoded builder with explicit charset percent-encoding (space -> '+')
        public static string urlencode_form (HashTable<string,string> form, string charset) throws Error {
            StringBuilder sb = new StringBuilder ();
            bool first = true;
            foreach (var key in form.get_keys ()) {
                var value = form[key] ?? "";
                string pair = urlencode_pair (key, value, charset);
                if (!first) sb.append_c ('&');
                sb.append (pair);
                first = false;
            }
            return sb.str;
        }

        private static string urlencode_pair (string key, string value, string charset) throws Error {
            string enc_key = percent_encode_bytes (string_to_bytes (key, charset));
            string enc_val = percent_encode_bytes (string_to_bytes (value, charset));
            return enc_key + "=" + enc_val;
        }

        // Convert UTF-8 string to target charset raw bytes
        private static uint8[] string_to_bytes (string s, string charset) throws Error {
            size_t br = 0; size_t bw = 0;
            // Convert returns raw bytes in 'string' container; use strlen to get length
            string outbin = GLib.convert (s, -1, charset, "UTF-8", out br, out bw);
            size_t n = (size_t) Posix.strlen (outbin); // stop at first NUL (none expected)
            unowned uint8[] raw = (uint8[]) outbin.data;
            uint8[] copy = new uint8[n];
            for (size_t i = 0; i < n; i++) copy[i] = raw[i];
            return copy;
        }

        // Percent-encode arbitrary bytes for x-www-form-urlencoded (space -> '+', unreserved stays plain)
        private static string percent_encode_bytes (uint8[] data) {
            StringBuilder sb = new StringBuilder ();
            for (size_t i = 0; i < data.length; i++) {
                uint8 b = data[i];
                if (is_unreserved (b)) {
                    sb.append_c ((char) b);
                } else if (b == ' ') {
                    sb.append_c ('+');
                } else {
                    sb.append ("%" + hex2 (b));
                }
            }
            return sb.str;
        }

        private static bool is_unreserved (uint8 b) {
            // ALPHA / DIGIT / "-" / "." / "_" / "~"
            if ((b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z') || (b >= '0' && b <= '9')) return true;
            return (b == '-' || b == '.' || b == '_' || b == '~');
        }
        private static string hex2 (uint8 b) {
            const string HEX = "0123456789ABCDEF";
            char a = HEX[(b >> 4) & 0xF];
            char c = HEX[b & 0xF];
            return @"$a$c";
        }

        // -------------- Parsers --------------
        private static List<SubjectEntry> parse_subject (string text, Board board) {
            List<SubjectEntry> list = new List<SubjectEntry> ();
            var lines = text.split ("\n");
            foreach (var line in lines) {
                var raw = line.strip ();
                if (raw.length == 0) continue;
                // format: {threadkey}.dat<>タイトル (NNN)
                int idx_dat = raw.index_of (".dat<>");
                if (idx_dat <= 0) continue;
                string key = raw.substring (0, idx_dat);
                // rest: タイトル (NNN)
                string rest = raw.substring (idx_dat + ".dat<>".length);
                int idx_cnt = rest.last_index_of (" (");
                string title = rest;
                int count = 0;
                if (idx_cnt >= 0 && rest.has_suffix (")")) {
                    title = rest.substring (0, idx_cnt);
                    var cnt_str = rest.substring (idx_cnt + 2, rest.length - (idx_cnt + 2) - 1);
                    try { count = int.parse (cnt_str); } catch (Error e) { count = 0; }
                }
                string dat_url = board.dat_url (key);
                list.append (new SubjectEntry (key, title, count, dat_url, raw));
            }
            return list;
        }


        // &#9999;, &#x2713;, &gt; 等をデコード
        // なぜpangoを使わないのかというと、少し形式が違うから
        public static string decode_html_entities (string src) {
            // &...; 全体を1本で拾う
            var regex = new GLib.Regex ("&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);");
            var sb = new StringBuilder ();

            MatchInfo mi;
            int last_end = 0;

            // 直前に見つけた「高位サロゲート」用のバッファ
            uint pending_high_surrogate = 0;
            // 直前のエンティティの終了位置（サロゲートペアが「隣り合っている」か判定する用）
            int prev_entity_end = -1;

            regex.match (src, 0, out mi);
            while (mi.matches ()) {
                int start_pos, end_pos;
                mi.fetch_pos (0, out start_pos, out end_pos);

                // 直前のエンティティの終端〜今回のエンティティ開始までのプレーンテキストを追加
                sb.append (src.substring (last_end, start_pos - last_end));

                // 中身だけ（& と ; を除いた部分）
                var ent = mi.fetch (1);

                bool handled = false;   // エンティティを変換して出力できたかどうか

                // ----------------------------------------------------
                // 1) 数値参照（&#NNNN; / &#xHHHH;）
                // ----------------------------------------------------
                if (ent.length > 0 && ent[0] == '#') {
                    try {
                        uint code;

                        // 16進: &#xHHHH;
                        if (ent.length >= 3 && (ent[1] == 'x' || ent[1] == 'X')) {
                            var hex = "0x" + ent.substring (2);
                            code = uint.parse (hex);
                        } else {
                            // 10進: &#NNNN;
                            var dec = ent.substring (1);
                            code = (uint) int.parse (dec);
                        }

                        // ------- サロゲート＋サロゲートペア対応 --------

                        if (code >= 0xD800 && code <= 0xDBFF) {
                            // 高位サロゲート (high surrogate)
                            // すでに高位が残っていたら、とりあえず置換文字にして流す
                            if (pending_high_surrogate != 0) {
                                sb.append_unichar ((unichar) 0xFFFD);
                            }
                            pending_high_surrogate = code;
                            handled = true;   // まだ出力はしない（次の low を待つ）
                        } else if (code >= 0xDC00 && code <= 0xDFFF) {
                            // 低位サロゲート (low surrogate)
                            if (pending_high_surrogate != 0 && prev_entity_end == start_pos) {
                                // 直前に high があり、かつすぐ隣にある → サロゲートペアとして結合
                                uint high = pending_high_surrogate;
                                pending_high_surrogate = 0;

                                uint full = 0x10000
                                            + ((high - 0xD800) << 10)
                                            + (code - 0xDC00);

                                if (full <= 0x10FFFF) {
                                    sb.append_unichar ((unichar) full);
                                    handled = true;
                                }
                            } else {
                                // 単独の low サロゲート → 置換文字にしておく
                                sb.append_unichar ((unichar) 0xFFFD);
                                handled = true;
                            }
                        } else if (code <= 0x10FFFF) {
                            // 通常のコードポイント
                            if (pending_high_surrogate != 0) {
                                // 直前に high が余っていたら、ここで諦めて置換文字として吐く
                                sb.append_unichar ((unichar) 0xFFFD);
                                pending_high_surrogate = 0;
                            }
                            sb.append_unichar ((unichar) code);
                            handled = true;
                        } else {
                            // 0x10FFFF を超えていたら不正なので無視（handled = false のまま）
                        }

                    } catch (Error e) {
                        // parse に失敗したら handled = false のまま
                    }

                // ----------------------------------------------------
                // 2) 名前付きエンティティ (&amp; など)
                // ----------------------------------------------------
                } else {
                    unichar ch = 0;
                    switch (ent) {
                    case "lt":
                        ch = '<';
                        break;
                    case "gt":
                        ch = '>';
                        break;
                    case "amp":
                        ch = '&';
                        break;
                    case "quot":
                        ch = '"';
                        break;
                    case "apos":
                        ch = '\'';
                        break;
                    case "nbsp":
                        ch = (unichar) 0x00A0;
                        break;
                    default:
                        break;
                    }

                    if (ch != 0) {
                        if (pending_high_surrogate != 0) {
                            // high が余っていたらここで潰す
                            sb.append_unichar ((unichar) 0xFFFD);
                            pending_high_surrogate = 0;
                        }
                        sb.append_unichar (ch);
                        handled = true;
                    }
                }

                // ----------------------------------------------------
                // 3) 変換できなかったときは元の &XXXX; をそのまま残す
                // ----------------------------------------------------
                if (!handled) {
                    // high サロゲートが残っていたら先に吐いてリセット
                    if (pending_high_surrogate != 0) {
                        sb.append_unichar ((unichar) 0xFFFD);
                        pending_high_surrogate = 0;
                    }
                    sb.append (mi.fetch (0));   // "&...;" まるごと
                }

                last_end = end_pos;
                prev_entity_end = end_pos;  // 「次のエンティティが隣接しているか」判定用
                mi.next ();
            }

            // ループ後、まだ高位サロゲートが残っていたら置換文字にする
            if (pending_high_surrogate != 0) {
                sb.append_unichar ((unichar) 0xFFFD);
                pending_high_surrogate = 0;
            }

            // 残りを追加
            sb.append (src.substring (last_end));
            return sb.str;
        }


        public static string encode_html_entities (string src) {
            var sb = new StringBuilder ();

            int index = 0;
            unichar ch;

            while (src.get_next_char (ref index, out ch)) {
                // 絵文字など U+10000 以上だけエンティティにする
                if (ch > 0xFFFF || (ch >= 0xFE00 && ch <= 0xFE0F)) {
                    sb.append_printf ("&#%d;", (int) ch);
                } else {
                    sb.append_unichar (ch);
                }
            }

            return sb.str;
        }


    }

    public class DatLoader : Object {
        private FiveCh.Client client;

        public DatLoader () {
            client = new FiveCh.Client ();
        }

        /**
          * URL または dat URL から Board / threadkey を推定して1回分の DAT を取得。
          */
        public async Gee.ArrayList<ResRow.ResItem> load_from_url_async (string urlr, Cancellable? cancellable = null) throws Error {
            string url = urlr.strip ();

            string? board_key = FiveCh.Board.guess_board_key_from_url (url);
            string? site_base = FiveCh.Board.guess_site_base_from_url (url);
            if (board_key == null || site_base == null) {
                throw new IOError.FAILED (_("Invalid URL"));
            }

            // threadkey 抜き出し
            string? threadkey = guess_threadkey_from_url (url);
            if (threadkey == null) {
                throw new IOError.FAILED (_("Invalid URL"));
            }

            var board = new FiveCh.Board (site_base, board_key);

            // 全体を一気に読む
            var chunk = yield client.fetch_dat_async (board, threadkey, -1, cancellable);
            return parse_dat_text (chunk.text);
        }

        public static string? guess_threadkey_from_url (string url) {
            try {
                MatchInfo mi;
                // .../dat/1234567890.dat
                var r_dat = new GLib.Regex ("/dat/([0-9]+)\\.dat");
                if (r_dat.match (url, 0, out mi))
                    return mi.fetch (1);

                // .../read.cgi/board/1234567890/...
                var r_read = new GLib.Regex ("/read\\.cgi/[^/]+/([0-9]+)/");
                if (r_read.match (url, 0, out mi))
                    return mi.fetch (1);
            } catch (Error e) {
            }
            return null;
        }

        public static string? build_browser_url (string urlr) {
            string url = urlr.strip ();

            string? board_key = FiveCh.Board.guess_board_key_from_url (url);
            string? site_base = FiveCh.Board.guess_site_base_from_url (url);
            string? thread_key = guess_threadkey_from_url (url);
            if (board_key == null || site_base == null || thread_key == null) {
                throw new IOError.FAILED (_("Invalid URL"));
            }

            return site_base + "read.cgi/" + board_key + "/" + thread_key + "/";
        }

        private static Gee.ArrayList<ResRow.ResItem> parse_dat_text (string text) {
            var list = new Gee.ArrayList<ResRow.ResItem> ();
            var lines = text.split ("\n");
            uint idx = 1;

            foreach (var raw_line in lines) {
                var line = raw_line.strip ();
                if (line.length == 0) continue;

                // name<>mail<>date ID:xxxx<>body
                var parts = line.split ("<>");
                if (parts.length < 4) continue;

                // 先頭が "<NAME>" なら、その分だけ先頭を削る
                const string prefix = "<NAME>";
                if (parts[0].has_prefix (prefix)) {
                    parts[0] = parts[0].substring (prefix.length);
                }

                string name = "<b>" + parts[0] + "</b>";

                //name = Client.decode_html_entities (name);
                string mail = Client.decode_html_entities (parts[1]);
                string date_id = Client.decode_html_entities (parts[2]);

                // DATの改行＆最低限のタグ処理
                string body = parts[3]
                    .replace (" <br> ", "\n")
                    .replace ("<br>", "\n");
                try {
                    var tag_rx = new GLib.Regex ("<[^>]+>");
                    body = tag_rx.replace (body, -1, 0, "");
                } catch (Error e) {
                    // タグ除去失敗時はそのまま
                }
                body = Client.decode_html_entities (body).strip ();
//print(body+"\n");
                string id = "";
                // date_id から "ID:xxxxx" を抜く（簡易）
                int pos = date_id.index_of ("ID:");
                if (pos >= 0) {
                    id = date_id.substring (pos + 3);
                    date_id = date_id.substring (0, pos);
                }

                var post = new ResRow.ResItem (idx++, name, mail, date_id, id, body);
                list.add (post);
            }
            return list;
        }
    }

    /**
     * DAT本文から Span 列を作成。
     * - ">>123" を REPLY
     * - "http(s)://..." を URL
     * それ以外は NORMAL
     */
    public class SpanBuilder {

        // Regex は遅延初期化（例外はここで握りつぶして null 許容）
        private static GLib.Regex? _token_regex = null;

        private static GLib.Regex? get_token_regex () {
            if (_token_regex != null)
                return _token_regex;

            try {
                // >>数字 or URL
                _token_regex = new GLib.Regex (
                    // >>1 / >>1-3 / >>1,2,3 / >>1-3,5-7,...
                    "(>>(?:[0-9]+(?:-[0-9]+)?(?:,[0-9]+(?:-[0-9]+)?)*))|(https?://(?:[A-Za-z0-9-]+\\.)+[A-Za-z]{2,}(?::[0-9]{2,5})?(?:/[^\\s<>\"']*)?)|(ID:[A-Za-z0-9]+)",
                    GLib.RegexCompileFlags.CASELESS | GLib.RegexCompileFlags.MULTILINE
                );
            } catch (Error e) {
                // 失敗した場合は null を保持しておく
                _token_regex = null;
            }
            return _token_regex;
        }

        public static Gee.ArrayList<Span> build (string raw_body) {
            var spans = new Gee.ArrayList<Span> ();

            string body = raw_body;

            var token_rx = get_token_regex ();

            // Regex生成に失敗していた場合は全部NORMALで返す
            if (token_rx == null) {
                if (body.length == 0) {
                    return spans;
                }
                spans.add (new Span (body, SpanType.NORMAL));
                return spans;
            }

            MatchInfo mi;
            int last = 0;

            token_rx.match (body, 0, out mi);
            while (mi.matches ()) {
                int start, end;
                mi.fetch_pos (0, out start, out end);

                if (start > last) {
                    var plain = body.substring (last, start - last);
                    if (plain.length > 0)
                        spans.add (new Span (plain, SpanType.NORMAL));
                }

                var full = mi.fetch (0);
                var g_reply = mi.fetch (1);
                var g_url = mi.fetch (2);
                var g_id = mi.fetch(3);

                if (g_reply != null && g_reply.length > 0) {
                    string num = g_reply.substring (2);
                    spans.add (new Span (full, SpanType.REPLY, num));
                } else if (g_url != null && g_url.length > 0) {
                    spans.add (new Span (full, SpanType.URL, full));
                } else if (g_id != null && g_id.length > 0){
                    spans.add (new Span (full, SpanType.ID, full));
                } else {
                    spans.add (new Span (full, SpanType.NORMAL));
                }

                last = end;
                mi.next ();
            }

            if (last < body.length) {
                var tail = body.substring (last);
                if (tail.length > 0)
                    spans.add (new Span (tail, SpanType.NORMAL));
            }

            if (spans.size == 0 && body.length > 0) {
                spans.add (new Span (body, SpanType.NORMAL));
            }

            return spans;
        }
    }

    // 1回だけ読み込みます。UAをファイルから取得
    void set_default_ua () {
        if (ua_text == null) {
            try {
                FileUtils.get_contents (ua, out ua_text);
            } catch (FileError e) {
                ua_text = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36";
                // FileError.NOENT
                if (e.code == FileError.NOENT) {
                    try {
                        FileUtils.set_contents (ua, ua_text);
                    } catch (FileError e2) {
                    }
                } else {
                }
            }
        }
        ua_text = ua_text.chomp ();
    }

    string default_browser_ua () {
        return ua_text;
    }
}

using GLib;
using Soup;
using Posix;

namespace FiveCh {
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
        public string charset { get; set; default = "CP932"; }
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
        public string? cookie_path  { get; set; } // optional persistent jar path

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
        private string ensure_board_base () {
            // Construct https://{host}/{board_key}/
            var board_base = ensure_site_base () + board_key + "/";
            return board_base;
        }

        public static string default_browser_ua () {
            // Safe default: browser-like UA recommended for posting on 5ch.
            // You may replace with a runtime-detected UA string if desired.
            return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36";
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
        public Session session { get; private set; }
        public CookieJar cookiejar { get; private set; }

        public Client (string? cookie_path = null, string? user_agent = null) {
            session = new Session ();
            session.user_agent = user_agent ?? Board.default_browser_ua ();

            if (cookie_path != null && cookie_path != "") {
                cookiejar = new CookieJarText (cookie_path, false);
            } else {
                cookiejar = new CookieJar ();
            }
            session.add_feature (cookiejar);

            // Follow redirects automatically (default true). Compression is automatic.
        }

        // -------------- SUBJECT.TXT --------------
        public async List<SubjectEntry> fetch_subject_async (Board board, Cancellable? cancel = null) throws Error {
            var url = board.subject_url ();
            var bytes = yield send_get_bytes_async (url, board.user_agent, null, cancel);
            string __enc_tmp; var text = decode_text_guess_japanese (bytes, out __enc_tmp);
            return parse_subject (text, board);
        }

        // -------------- SETTING.TXT --------------
        public async HashTable<string,string> fetch_setting_async (Board board, Cancellable? cancel = null) throws Error {
            var url = board.setting_url ();
            var bytes = yield send_get_bytes_async (url, board.user_agent, null, cancel);
            string __enc_tmp;
            var text = decode_text_guess_japanese (bytes, out __enc_tmp);
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
        public async string post_async (Board board,
                                       string bbs,
                                       string? key,
                                       string message,
                                       string from = "",
                                       string mail = "",
                                       string? subject = null,
                                       PostOptions? options = null,
                                       Cancellable? cancel = null) throws Error {
            PostOptions opts;
            if (options == null) {
                opts = new PostOptions ();
            } else {
                opts = options;
            }

            var form = new HashTable<string,string> (str_hash, str_equal);
            if (subject != null) form["subject"] = subject;
            form["FROM"]   = from;
            form["mail"]   = mail;
            form["MESSAGE"] = message;
            if (key != null) form["key"] = key;
            form["bbs"]     = bbs;
            form["time"]    = ((int64) (get_real_time ()/1000000)).to_string ();
            form["submit"]  = opts.submit_label;

            // Percent-encode per selected charset
            string encoded = urlencode_form (form, opts.charset);

            var msg = new Message ("POST", board.bbs_cgi_url ());
            // Headers
            var ua = opts.user_agent_override ?? board.user_agent;
            msg.request_headers.replace ("User-Agent", ua);
            msg.request_headers.replace ("Content-Type", "application/x-www-form-urlencoded");
            if (opts.extra_headers != null) {
                foreach (var k in opts.extra_headers.get_keys ()) {
                    var v = opts.extra_headers[k];
                    msg.request_headers.replace (k, v);
                }
            }
            // Body (NOTE: body must be raw bytes; do not assume UTF-8)
            // We keep it as ASCII string since it's percent-encoded — safe in UTF-8 too.
            var bytes = bytes_from_string_ascii (encoded);
            msg.set_request_body_from_bytes ("application/x-www-form-urlencoded", bytes);

            var resp_bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, cancel);
            // 2ch互換はHTMLで応答することが多い。エラーメッセージ等をUTF-8推定→失敗なら日本語系にフォールバック。
            string __enc_post; string text = decode_text_guess_japanese (resp_bytes, out __enc_post);

            var status = msg.get_status ();
            if (!(status == 200 || status == 301 || status == 302)) {
                throw new IOError.FAILED ("POST failed: %u — %s\n%s".printf ((uint) status, msg.get_reason_phrase (), text));
            }
            return text;
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
            try {
                string s = (string) data; // treat as UTF-8 — may throw if invalid
                if (s.validate ()) { used_encoding = "UTF-8"; return s; }
            } catch (Error e) { /* fallthrough */ }

            string[] encs = { "CP932", "Shift_JIS", "EUC-JP", "ISO-2022-JP" };
            foreach (var enc in encs) {
                try {
                    string converted = convert_bytes (data, sz, "UTF-8", enc);
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
    }
}

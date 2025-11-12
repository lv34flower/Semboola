using GLib;
using Gtk;
using Pango;

public enum SpanType {
    NORMAL,
    REPLY, // >>123
    URL
}

public class Span : Object {
    public string text;
    public SpanType type;
    public string? payload;   // REPLY: レス番号 / URL: href
    public uint start_index;  // UTF-8バイトindex
    public uint end_index;

    public Span (string text, SpanType type, string? payload = null) {
        this.text = text;
        this.type = type;
        this.payload = payload;
    }

    public bool contains (uint index) {
        return index >= start_index && index < end_index;
    }
}

/**
    クリック可能ラベル
 */
public class ClickableLabel : Gtk.Box {
    public Gtk.Label inner_label;
    private Gee.ArrayList<Span> spans = new Gee.ArrayList<Span> ();

    public signal void span_left_clicked  (Span span);
    public signal void span_right_clicked (Span span, double x, double y);


    private bool _suppress_next_release = false;
    public ClickableLabel () {
        Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);

        inner_label = new Gtk.Label (null);
        inner_label.use_markup = true;
        inner_label.wrap = true;
        inner_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        inner_label.selectable = false;
        inner_label.xalign = 0.0f;
        inner_label.hexpand = true;
        inner_label.vexpand = false;
        this.append (inner_label);

        var click = new Gtk.GestureClick ();
        click.set_button (0); // 0=全ボタン/タッチを受ける
        click.released.connect ((n_press, x, y) => {
            // ここでだけ起動する（pressed では何もしない）
            var span = get_span_at (x, y);
            if (span == null) return;

            uint button = click.get_current_button ();
            if (button == Gdk.BUTTON_PRIMARY) {
                if (!this._suppress_next_release)  // 長押し直後の誤発火抑止
                    span_left_clicked (span);
            } else if (button == Gdk.BUTTON_SECONDARY) {
                span_right_clicked (span, x, y);
            }
            this._suppress_next_release = false; // 毎回リセット
        });
        inner_label.add_controller (click);

        // タッチの長押し＝右クリック相当
        var longp = new Gtk.GestureLongPress ();
        longp.pressed.connect ((x, y) => {
            var span = get_span_at (x, y);
            if (span == null) return;
            // コンテキスト（右クリック相当）を発火
            span_right_clicked (span, x, y);
            // この長押しに続く "released" ではリンクを開かない
            this._suppress_next_release = true;
        });
    }

    public void set_spans (Gee.Iterable<Span> new_spans) {
        spans.clear ();
        var sb = new StringBuilder ();
        uint index = 0;

        foreach (var s in new_spans) {
            s.start_index = index;

            var esc = Markup.escape_text (s.text);

            switch (s.type) {
            case SpanType.REPLY:
                // 青＋下線
                sb.append (@"<span foreground='#3060ff'><u>$esc</u></span>");
                break;
            case SpanType.URL:
                // 緑＋下線
                sb.append (@"<span foreground='#208020'><u>$esc</u></span>");
                break;
            default:
                sb.append (esc);
                break;
            }

            // UTF-8バイト長（Gtk/Pangoの index と一致）
            index += (uint) s.text.length;
            s.end_index = index;
            spans.add (s);
        }

        inner_label.set_markup (sb.str);
    }

    private Span? get_span_at (double x, double y) {
        if (spans.size == 0)
            return null;

        var layout = inner_label.get_layout ();
        if (layout == null)
            return null;

        int ox, oy;
        inner_label.get_layout_offsets (out ox, out oy);

        // GestureClick の x,y は inner_label 座標系(px)
        int lx = (int) (x * Pango.SCALE) - ox;
        int ly = (int) (y * Pango.SCALE) - oy;

        int index, trailing;
        if (!layout.xy_to_index (lx, ly, out index, out trailing))
            return null;

        uint uindex = (uint) index;

        foreach (var s in spans) {
            if (s.contains (uindex))
                return s;
        }
        return null;
    }
}



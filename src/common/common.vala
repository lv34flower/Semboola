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

}

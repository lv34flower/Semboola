class AhoMatcher : Object {
    private class Node : Object {
        public Gee.HashMap<unichar, int> next = new Gee.HashMap<unichar, int> ();
        public int fail = 0;
        public bool output = false;
    }

    private Gee.ArrayList<Node> nodes = new Gee.ArrayList<Node> ();
    private bool built = false;

    public AhoMatcher () {
        nodes.add (new Node ());
    }

    public void clear () {
        nodes.clear ();
        nodes.add (new Node ());
        built = false;
    }

    public void add_pattern (string pat) {
        if (pat == null || pat == "")
            return;

        built = false;

        int state = 0;
        for (unowned string p = pat; p.get_char () != 0; p = p.next_char ()) {
            unichar c = p.get_char ();

            // 値型(int)の get() だけに頼ると「未登録=0」に見える環境があるので
            // has_key() で存在判定してから get() する。
            if (!nodes[state].next.has_key (c)) {
                nodes.add (new Node ());
                int new_state = nodes.size - 1;
                nodes[state].next.set (c, new_state);
                state = new_state;
            } else {
                state = nodes[state].next.get (c);
            }
        }
        nodes[state].output = true;
    }

    private void build () {
        if (built)
            return;

        built = true;

        // BFS で failure link を作る
        GLib.Queue<int> q = new GLib.Queue<int> ();

        foreach (var e in nodes[0].next.entries) {
            int s = e.value;
            nodes[s].fail = 0;
            q.push_tail (s);
        }

        while (q.get_length () > 0) {
            int r = q.pop_head ();

            foreach (var e in nodes[r].next.entries) {
                unichar a = e.key;
                int s = e.value;

                q.push_tail (s);

                int state = nodes[r].fail;
                while (state != 0 && !nodes[state].next.has_key (a)) {
                    state = nodes[state].fail;
                }

                nodes[s].fail = nodes[state].next.has_key (a) ? nodes[state].next.get (a) : 0;
                nodes[s].output = nodes[s].output || nodes[nodes[s].fail].output;
            }
        }
    }

    public bool match (string text) {
        if (text == null || text == "")
            return false;

        if (nodes.size <= 1)
            return false;

        build ();

        int state = 0;
        for (unowned string p = text; p.get_char () != 0; p = p.next_char ()) {
            unichar c = p.get_char ();

            while (state != 0 && !nodes[state].next.has_key (c)) {
                state = nodes[state].fail;
            }

            if (nodes[state].next.has_key (c))
                state = nodes[state].next.get (c);

            if (nodes[state].output)
                return true;
        }

        return false;
    }
}

#!/usr/bin/env python3
"""Splice Icons/icons.json into deck.template.html -> loom-icons-deck.html."""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
data = open(os.path.join(HERE, "Icons", "icons.json")).read()
tpl = open(os.path.join(HERE, "deck.template.html")).read()

# </script> inside a <script type="application/json"> block would close it early
safe = data.replace("</", "<\\/")
out = os.path.join(HERE, "loom-icons-deck.html")
open(out, "w").write(tpl.replace("__DATA__", safe))
print("%s  %.0f KB" % (out, os.path.getsize(out) / 1024))

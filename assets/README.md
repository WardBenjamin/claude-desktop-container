# Assets

- `claude-black.png` — the app logo: an original greyscale "wiggly burst" mark on
  a neutral-grey rounded tile, in the radiating-sunburst visual family. It is an
  original design, not a reproduction of any brand logo. 1024x1024 RGBA.

Regenerate or edit it with the pure-stdlib generator (no dependencies):

```sh
python3 ../tools/make-logo.py claude-black.png
```

Tunable constants (ray count, wiggle amount, colors, sizes) are at the top of
`tools/make-logo.py`. `build-app.sh` consumes `claude-black.png` directly.

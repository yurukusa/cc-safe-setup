`cc-safe-demo.svg` — an animated terminal recording showing two real example
hooks blocking real disasters (a recursive delete over a source tree, and a
read of a credential file). Every block in the recording is the actual hook
running, with its real exit code and message — nothing is staged.
Regenerate:
```bash
asciinema rec -c "bash docs/demo/cc-safe-demo.sh" /tmp/cc-safe-demo.cast --overwrite
npx svg-term-cli --in /tmp/cc-safe-demo.cast --out docs/demo/cc-safe-demo.svg --window --width 80 --height 24
```
Embeddable in the project README or articles (animated SVG, no JS).

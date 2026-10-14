Warning: fs was declared with const; use let for reassignable variables.
# Retro TV fair presentation

- `deck_redesigned_source.pptx` preserves the supplied presentation.
- `Retro-TV-Project-Fair-Deck.pptx` is the refreshed 29-slide project-fair deck.
- `update_fair_deck.py` applies the same wording and palette refresh to the source file.

Run the refresh from this folder with:

```sh
python3 update_fair_deck.py deck_redesigned_source.pptx Retro-TV-Project-Fair-Deck.pptx
```

The deck reflects the current 22-inch HDMI monitor, replacement Raspberry Pi 4,
completed frame as reported by the user, Arduino Uno controls, direct GPIO3
power button, and current 264-entry IPTV playlist. LIVE TV freezing is described
as ongoing playback work. The color palette uses warm charcoal, cream, terracotta,
brass and muted teal; slide layout and photos are retained.

The refresh was checked for ZIP integrity, XML parsing and expected project facts.
PDF rendering and physical-device playback were not verified in this environment.

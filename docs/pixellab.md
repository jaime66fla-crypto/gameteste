# PixelLab operator animations

`PIXELLAB_API_KEY` belongs in the repository's GitHub Actions secrets. The workflow passes it only to the offline asset generator. The browser and the Cloudflare game never need it.

The generator reuses `operator-directions.png`, prepares a transparent 96px reference for each direction, and requests walk/run loops with eight generated frames per direction. PixelLab v3 also returns the input frame; the importer removes that extra frame. All PNG strips share a fixed foot anchor. Review the GIFs before copying the PNG strips and manifest into `public/assets/player/animations/`.

The workflow only uploads review artifacts. It does not commit or deploy generated images. `preview` generates one direction, `all` generates all eight, and `check` validates authentication without generating images. `--resume-job` retrieves a completed job for inspection; `--reuse-walk-job` reuses the first southeast walking generation while completing the set. Existing jobs are not resubmitted after ambiguous connection errors.

Run local checks with:

```sh
python -m unittest discover -s tests -p 'test_pixellab*.py' -v
node tests/isometric.test.cjs
```

For the game, pack the sixteen strips into `operator-motion.png` (768×1536, walk rows 0–7 and run rows 8–15) and the idle references into `operator-idle.png` (768×96). The manifest gives each direction its row. These two packed assets load in `player-art.js`. The original directional sprite remains available while sheets load or if any direction is missing. Animation playback follows the distance actually travelled, so collisions do not animate a walking loop in place. Movement uses a short acceleration/deceleration transition for keyboard and touch input alike.

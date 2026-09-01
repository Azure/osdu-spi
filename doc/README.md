# Documentation

The site is built with [MkDocs](https://www.mkdocs.org/) from the Markdown
sources in `doc/src`. The `docs.yml` workflow builds it with `--strict`, so a
broken link or a page missing from the nav fails the build. Run the same build
locally before opening a pull request.

## How to locally test the documentation

You can test the site with Docker or with `mkdocs` installed directly. In both
cases run the commands inside the `doc` folder.

With Docker, you just need to execute the following command and point your
browser to `http://127.0.0.1:8000/`:

``` bash
docker run --rm -v "$(pwd):$(pwd)" -w "$(pwd)" -p 8000:8000 \
    minidocks/mkdocs \
    mkdocs serve -a 0.0.0.0:8000
```

If you have installed `mkdocs` directly in your workstation, you can simply run:

``` bash
mkdocs serve
```

Even in this case, point your browser to `http://127.0.0.1:8000/`.

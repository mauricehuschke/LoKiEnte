# Build a team ticket summary

[Deutsch](README.de.md)

## Run the completed feature

This folder contains the verified reference implementation. To develop the feature in Kilo yourself, download the [starter ZIP](https://raw.githubusercontent.com/mauricehuschke/LoKiEnte/main/examples/support-board-starter.zip). To inspect the reference, run `node --test` here, then `node src/server.cjs`. The [verification record](verification.json) shows the measured outcomes and scope.

## Try the feature request

This standalone Node.js exercise uses generated tickets. Start from a fresh copy of the starter, open its folder in the LoKiEnte desktop launcher and paste this request into Kilo’s `shadow-chat`.

> Add a team ticket summary to this local support board. On the homepage and at GET /api/summary show open and closed counts for team-visible tickets. For the supplied data both views must show 2 open and 1 closed. An empty queue shows two zeroes. Internal tickets must not affect either count. Neither view may expose titles or contact fields. Preserve GET /health. Only change src/tickets.cjs, src/server.cjs and src/page.cjs plus separate unit and integration tests. Use the Feature workflow with independent test, security, integration and final reviews. Run the tests locally. No new dependencies or external network access.

Watch the roles and results in Kilo or `LOKI-STATUS.md`. After verification, run `node src/server.cjs` and open [the board](http://127.0.0.1:4318/) and [the JSON endpoint](http://127.0.0.1:4318/api/summary). Stop the local server with Ctrl+C. Use `node --test` to repeat the tests.

For a downloaded starter, extract it to its own folder. From the folder containing `package.json`, create its initial local Git commit before selecting it in the launcher:

```powershell
git init
git add .
git -c user.name=Example -c user.email=example@localhost -c commit.gpgsign=false commit -m "Start support board"
```

# PouchDB sync job (control)

[![Travis Build][travis]](https://travis-ci.org/nhz-io/nhz-io-pouch-db-sync-job)
[![NPM Version][npm]](https://www.npmjs.com/package/@nhz.io/pouch-db-sync-job)

## Install

```bash
npm i -S @nhz.io/pouch-db-sync-job
```

## Usage

> Intended to be used with [pouchdb-job-scheduler]

```js
const PouchDB = require 'pouchdb'
const sync = require('@nhz.io/pouch-db-sync-job')

const startJob = sync { /* PouchDb sync options */}, databaseA, databaseB
const job = startJob { PouchDB }

...

const res = await job

...
```
## Literate Source

### Imports

    curryN = require 'curry-n'

### Helpers

    assign = (sources...) -> Object.assign {}, sources...

    isString = (maybeString) -> typeof maybeString is 'string'

    getter = (obj, name, fn) -> Object.defineProperty obj, name, {
      configurable: true, enumerable: true, get: fn
    }

### Definitions

> Global Job UID

    uid = 0

> Sync defaults

    def = {

      live: false

      retry: false

      since: 0

    }

### Job generator

    pouchDbSyncJob = (options, databaseA, databaseB, ctx) ->

> Hoist `stop` and `sync` (for Promise below)

      stop = sync = null

> Get pouch from context or global (context comes from queue manager, if any)

      PouchDB = ctx.PouchDB or PouchDB

> Preload databases

      databaseA = new PouchDB databaseA if isString databaseA

      databaseB = new PouchDB databaseB if isString databaseB

> Assign defaults

      options = assign def, options

#### Create and start the job

Job is actually a promise extended with extra properties.

Promise states meaning:

* Promise resolved &rarr; sync has finished (Connection might still be open)
* Promise rejected
  * `err` is empty &rarr; sync was cancelled
  * otherwise, `err` contains the reason and will be set to `job.error`

>

      job = new Promise (resolve, reject) ->

        sync = ctx.PouchDB.sync databaseA, databaseB, assign options

> Job stopper (`err` is optional - no `err` means manual stop)

        stop = (err) ->

          sync.cancel()

          return if job.done

          job.done = true

          job.error = err or false

          reject job.error

          return job

> Job completer

        complete = (info) ->

          job.info = info if info

          return if job.done

          job.done = true

          job.error = false

> Create result by stripping promise from the job and aliasing job.info

          resolve getter (assign job), 'info', () -> job.info

#### PouchDB sync events

        sync.on 'error', stop

        sync.on 'denied', stop


> Live syncs fire `complete` only when cancelled

        sync.on 'complete', complete


> Applies only to `retry` syncs

        sync.on 'active', -> job.started = true

        sync.on 'paused', (err) -> if err then stop err else complete()

        sync.then(complete).catch(stop)

> Extend the promise and return

      uid = uid + 1

      Object.assign job, {
        uid, options, stop, sync, databases: [ databaseA, databaseB ]
      }

## Exports (Curried)

    module.exports = curryN 4, pouchDbSyncJob

## Tests

    test = require 'tape-async'

    PouchDB = require 'pouchdb-memory'

    pouchDbSyncJob = module.exports

    mkdb = (s = 1, e = 3) ->

      db = new PouchDB "db-#{ Math.random().toString().slice 2 }"

      await db.put { _id: "doc-#{ i }" } for i in [s..e]

      db

> **Job completion**

    test 'job completion', (t) ->

> One-Shot

      dbA = await mkdb 1, 3

      dbB = await mkdb 4, 6

      startJob = pouchDbSyncJob {}, dbA, dbB

      job = startJob { PouchDB }

      res = await job

      t.equals res.info, job.info

      t.deepEqual (await dbA.allDocs()), (await dbB.allDocs()), 'docs match'

      job.stop()

      t.equals res.info, job.info

      t.equals res.info.push.status, 'complete'
      t.equals res.info.pull.status, 'complete'

> Live

      dbA = await mkdb 1, 3

      dbB = await mkdb 4, 6

      startJob = pouchDbSyncJob { live: true, retry: true }, dbA, dbB

      res = await job = startJob { PouchDB }

      t.equals res.info, job.info

      t.deepEqual (await dbA.allDocs()), (await dbB.allDocs()), 'docs match'

      t.equals job.started, true

      t.false job.sync.canceled

      job.stop()

      t.true job.sync.canceled


> **Job failure**

    test 'job failure', (t) ->

      db = await mkdb 1, 3

      startJob = pouchDbSyncJob { live: true, retry: false }, 'http://foo-not-found', db

      try
        await job = startJob { PouchDB }

        t.fail()

      catch err

        t.equals err.status, 500

## Version 1.0.0

## License [MIT](LICENSE)

[travis]: https://img.shields.io/travis/nhz-io/nhz-io-pouch-db-sync-job.svg?style=flat
[npm]: https://img.shields.io/npm/v/@nhz.io/pouch-db-sync-job.svg?style=flat

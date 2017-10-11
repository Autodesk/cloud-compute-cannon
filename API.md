	# Cloud Compute Cannon API

All routes are prefixed by the `<domain>:<port>/api/rpc`

### GET `/job-stats?jobId=<jobId>`

Returns the job stats:

```
	{
	  "id": "_",
	  "result": {
	    "recieved": "2017-02-10T14:18:21 PST",
	    "duration": "7.219s",
	    "uploaded": "0.129s",
	    "finished": "2017-02-10T14:18:28 PST",
	    "error": "null",
	    "attempts": [
	      {
	        "enqueued": "2017-02-10T14:18:21 PST",
	        "dequeued": "2017-02-10T14:18:21 PST",
	        "inputs": "1.626s",
	        "image": "0.918s",
	        "inputsAndImage": "2.544s",
	        "container": "1.198s",
	        "outputs": "3.228s",
	        "exitCode": 0,
	        "error": "null"
	      }
	    ]
	  },
	  "jsonrpc": "2.0"
	}
```

### GET `/stats-minimal-job`

Returns the job stats of a minimal job that copies a small input file to an output file.


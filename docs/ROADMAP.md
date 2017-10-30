Planned features:

 - Properly shut down workers + server when remote tests are complete.
 - Access control: server remote API access requires an access token.
 - TLS over the remote API.
 - Fix job limitation due to each Job object creating its own redis connection.
 - CLI/Remote API to show job stdout/err
 - CLI to auto set up a local stack.
 - CLI assumes local stack.

Failures to test for:

 - Bad inputs:
 	- url input returns an non 200 response
 	- the rest of the inputs are either inline, or part of the multipart request, it's difficult to see how they fail.
 - Inputs fail to copy to storage
 - The worker assigned goes down as the inputs are copied from storage to the worker
 - Inputs fail to copy to the worker, or space is exceeded
 - There is no docker image (this one cannot be restarted)
 - The docker image fails to download
 - The docker container is misconfigured
 - The docker container takes too long
 - Outputs fail to copy
 - Stdout/err retrieval fails
 - Fails to write results.json

Job failure:
	- if a job fails, and it's not an error accounted for, then the worker should be checked, and if the worker cannot be reached, then requeue, otherwise fail for real.

Planned features:

 - Properly shut down workers + server when remote tests are complete.
 - CloudFront or whatever script to set up a proper network with correct permissions etc.
 - Access control: server remote API access requires an access token.
 - TLS over the remote API.
 - Fix job limitation due to each Job object creating its own redis connection.
 - CLI/Remote API to show job stdout/err
 - CLI to auto set up a local stack.
 - CLI assumes local stack.
 - Remote setup: create a VPC, security groups, port access, etc with a single command. How will users work here?

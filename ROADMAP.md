Planned features:

 - Properly shut down workers + server when remote tests are complete.
 - Access control: server remote API access requires an access token.
 - TLS over the remote API.
 - Fix job limitation due to each Job object creating its own redis connection.
 - CLI/Remote API to show job stdout/err
 - CLI to auto set up a local stack.
 - CLI assumes local stack.

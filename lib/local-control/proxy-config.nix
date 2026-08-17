_: {
  mkProxyConfig =
    {
      bindAddress,
      dashboardDirectory,
      webPort,
      apiPort,
      proxyPort,
    }:
    ''
      {
        admin off
        auto_https off
        servers {
          protocols h1 h2
          strict_sni_host insecure_off
        }
      }

      http://127.0.0.1:${toString webPort} {
        bind 127.0.0.1

        handle /api/* {
          reverse_proxy 127.0.0.1:${toString apiPort} {
            # Browser requests never receive or carry the control-plane secret.
            # The loopback-only proxy replaces any caller-provided value with
            # the credential loaded by its owner-only secure launcher.
            header_up Authorization "Bearer {$LOCAL_CONTROL_BROWSER_CREDENTIAL}"
            header_up -X-Agent-Proxy-Attestation
            header_up -X-Client-Certificate-Fingerprint
          }
        }

        handle {
          root * "${dashboardDirectory}"
          try_files {path} /index.html
          file_server
        }
      }

      # The private edge is addressed by IP. Clients therefore do not send SNI.
      # A host-qualified Caddy site would scope client authentication to an SNI
      # matcher and silently leave IP clients on an unauthenticated fallback TLS
      # policy. Keep the listener catch-all and constrain it with `bind` instead.
      https://:${toString proxyPort} {
        bind ${bindAddress}
        tls {$LOCAL_CONTROL_PROXY_CERT} {$LOCAL_CONTROL_PROXY_KEY} {
          client_auth {
            trust_pool file {$LOCAL_CONTROL_PROXY_CA}
            mode require_and_verify
          }
        }

        @agent_paths path \
          /api/agent/enroll \
          /api/agents/*/heartbeat \
          /api/agents/*/commands* \
          /api/agents/*/endpoints/*/commands/*:consume
        handle @agent_paths {
          request_header -X-Client-Certificate-Fingerprint
          request_header -X-Agent-Proxy-Attestation
          reverse_proxy 127.0.0.1:${toString apiPort} {
            header_up X-Client-Certificate-Fingerprint {http.request.tls.client.fingerprint}
            header_up X-Agent-Proxy-Attestation {$SERVICE_PROXY_ATTESTATION}
          }
        }
        respond 404
      }
    '';
}

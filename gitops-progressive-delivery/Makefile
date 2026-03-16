.PHONY: validate lint smoke-test kind-up

validate:
	bash -n scripts/*.sh
	python3 -c "import glob,yaml; [list(yaml.safe_load_all(open(p))) for p in glob.glob('.github/workflows/*.yml') + glob.glob('argocd/**/*.yaml', recursive=True) + glob.glob('argo-rollouts/**/*.yaml', recursive=True) + glob.glob('environments/**/*.yaml', recursive=True) + glob.glob('helm-charts/**/*.yaml', recursive=True)]; print('YAML parses successfully.')"
	for svc in order-service payment-service saga-orchestrator; do test -f services/$$svc/package.json && test -f services/$$svc/package-lock.json && test -f services/$$svc/Dockerfile && test -f services/$$svc/server.js; done

lint:
	for svc in order-service payment-service saga-orchestrator; do (cd services/$$svc && node --check server.js); done

smoke-test: lint
	for svc in order-service payment-service saga-orchestrator; do \
	  (cd services/$$svc && node server.js & pid=$$!; sleep 2; curl -fsS http://127.0.0.1:8080/health/ready >/dev/null; kill $$pid); \
	done

kind-up:
	./scripts/bootstrap-dev-cluster.sh

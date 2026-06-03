.PHONY: validate bootstrap smoke gameday clean-experiments list-experiments local-up local-down local-setup

validate:
	bash -n scripts/bootstrap.sh
	bash -n scripts/run-experiment.sh
	python3 -c "import glob,yaml; [yaml.safe_load(open(p)) for p in glob.glob('chaos-mesh/experiments/**/*.yaml', recursive=True)]; print('Chaos manifests parse successfully.')"

bootstrap:
	bash scripts/bootstrap.sh

smoke:
	PROMETHEUS_URL=$${PROMETHEUS_URL:-http://localhost:9090} bash scripts/run-experiment.sh chaos-mesh/experiments/network/latency-order-service.yaml --force

gameday:
	kubectl apply -f litmus/workflows/resilience-gameday.yaml
	@echo "Game day started. Watch progress:"
	@echo "  kubectl get chaosengine resilience-gameday -n litmus -w"
	@echo "  See docs/runbooks/gameday-playbook.md for full guidance."

clean-experiments:
	kubectl delete networkchaos,podchaos,stresschaos,iochaos,timechaos,httpchaos --all -n chaos-testing 2>/dev/null || true
	@echo "All active chaos experiments removed."

list-experiments:
	@echo "Available experiments:"
	@find chaos-mesh/experiments -name "*.yaml" | sort | while read f; do \
	  risk=$$(python3 -c "import yaml; d=yaml.safe_load(open('$$f')); print(d.get('metadata',{}).get('labels',{}).get('risk-level','?'))"); \
	  kind=$$(python3 -c "import yaml; d=yaml.safe_load(open('$$f')); print(d.get('kind','?'))"); \
	  echo "  $$f  [$$kind, risk=$$risk]"; \
	done

local-up:
	docker compose -f docker/docker-compose.yml up -d
	@echo "Stack ready:"
	@echo "  order-service:   http://localhost:3000/health"
	@echo "  payment-service: http://localhost:3001/health"
	@echo "  Prometheus:      http://localhost:9090"
	@echo "  Grafana:         http://localhost:3030  (admin/admin)"

local-down:
	docker compose -f docker/docker-compose.yml down

local-setup:
	bash scripts/local-setup.sh

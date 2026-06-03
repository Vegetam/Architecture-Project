.PHONY: validate compose-config kind-up smoke-test

validate:
	bash -n scripts/kind-up.sh
	bash -n scripts/smoke-test.sh
	python3 -c "import glob,yaml; [list(yaml.safe_load_all(open(p))) for p in glob.glob('.github/workflows/*.yml') + glob.glob('k8s/**/*.yaml', recursive=True)]; print('Observability manifests parse successfully.')"

compose-config:
	docker compose -f docker/docker-compose.yml config --quiet

kind-up:
	bash scripts/kind-up.sh

smoke-test:
	bash scripts/smoke-test.sh

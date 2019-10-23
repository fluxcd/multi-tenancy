package main

import data.kubernetes

name = input.metadata.name

annotations {
  input.spec.selector.template.metadata.annotations["prometheus.io/scrape"]
}

warn[msg] {
  kubernetes.is_deployment
  not annotations
  msg = sprintf("Deployment %s should set prometheus.io/scrape pod annotation", [name])
}

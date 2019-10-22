package main

import data.kubernetes

deny[msg] {
	kubernetes.containers[container]
	[image_name, "latest"] = kubernetes.split_image(container.image)
	msg = sprintf("%s in the %s %s has an image, %s, using the latest tag", [container.name, kubernetes.kind, image_name, kubernetes.name])
}

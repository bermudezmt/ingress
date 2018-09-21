/*
Copyright 2018 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package canary

import (
	extensions "k8s.io/api/extensions/v1beta1"

	"k8s.io/ingress-nginx/internal/ingress/annotations/parser"
	"k8s.io/ingress-nginx/internal/ingress/errors"
	"k8s.io/ingress-nginx/internal/ingress/resolver"
)

type canary struct {
	r resolver.Resolver
}

// Config returns the configuration rules for setting up the Canary
type Config struct {
	Enabled bool
	Weight  int
	Header  string
	Cookie  string
}

// NewParser parses the ingress for canary related annotations
func NewParser(r resolver.Resolver) parser.IngressAnnotation {
	return canary{r}
}

// Parse parses the annotations contained in the ingress
// rule used to indicate if the canary should be enabled and with what settings
func (c canary) Parse(ing *extensions.Ingress) (interface{}, error) {
	enabled, err := parser.GetBoolAnnotation("canary", ing)
	if err != nil {
		return nil, err
	}

	weight, err := parser.GetIntAnnotation("canary-weight", ing)
	if err != nil {
		return nil, err
	}

	header, err := parser.GetStringAnnotation("canary-by-header", ing)
	if err != nil {
		return nil, err
	}

	cookie, err := parser.GetStringAnnotation("canary-by-cookie", ing)
	if err != nil {
		return nil, err
	}

	// return error if canary configured but disabled
	if !enabled && (weight > 0 || len(header) > 0 || len(cookie) > 0) {
		return nil, errors.New("invalid canary configuration")
	}

	return &Config{enabled, weight, header, cookie}, nil
}

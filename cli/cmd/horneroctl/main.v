module main

import hornero_cli
import os

fn main() {
	code := hornero_cli.dispatch(os.args)
	exit(code)
}

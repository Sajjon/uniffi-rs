#![cfg(test)]
mod test_of_bindgen;

use crate::{
    bindings::KotlinBindingGenerator, BindingGenerator, Component, ComponentInterface,
    GenerationSettings,
};

use super::gen_kotlin;
use camino::Utf8PathBuf;
use gen_kotlin::{generate_bindings, Config};

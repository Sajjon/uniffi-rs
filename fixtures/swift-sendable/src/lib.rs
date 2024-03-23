/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

use std::{collections::HashMap, sync::Arc};

#[derive(Clone, Debug, uniffi::Object)]
pub struct MyObject {
    pub string: String,
}

#[uniffi::export]
impl MyObject {
    #[uniffi::constructor]
    pub fn new(string: String) -> Self {
        Self { string }
    }
}

#[derive(Clone, Debug, uniffi::Record)]
struct RecordWithoutObjects {
    string: String,
    vec: Vec<bool>,
    u: u64,
    map: HashMap<String, Vec<u16>>,
}

#[derive(Clone, Debug, uniffi::Record)]
struct RecordWithObject {
    string: String,
    obj: Arc<MyObject>,
}

#[derive(Clone, Debug, uniffi::Enum)]
enum EnumWithoutObjects {
    RecordWithoutObjects(RecordWithoutObjects),
    String(String),
    Bool(bool),
    Vec(Vec<u16>),
}

#[derive(Clone, Debug, uniffi::Enum)]
enum EnumWithIndirectObject {
    RecordWithObjects(RecordWithObject),
    String(String),
    Bool(bool),
    Vec(Vec<u16>),
}

#[derive(Clone, Debug, uniffi::Enum)]
enum EnumWithObject {
    VariantObject(Arc<MyObject>),
    VariantString(String),
    VariantBool(bool),
    VariantVec(Vec<u16>),
}

uniffi::include_scaffolding!("test");

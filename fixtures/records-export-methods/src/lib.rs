/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#[derive(uniffi::Record)]
struct Person {
    height: f32,
    weight: f32,
}

impl Person {

}

uniffi::include_scaffolding!("records_export_methods");

// OpenrowDB Linux shell — GTK 4 + libadwaita (native GNOME look).

use gtk4::prelude::*;
use gtk4::{glib, ApplicationWindow};
use libadwaita::prelude::*;
use libadwaita::{Application, HeaderBar, StyleManager, ViewStack, ViewStackPage};
use openrowdb_core::SqlDialect;

const APP_ID: &str = "dev.txtdrprogrammer.OpenrowDB";

fn main() -> glib::ExitCode {
    let app = Application::builder().application_id(APP_ID).build();

    app.connect_activate(|app| {
        let style = StyleManager::default();
        style.set_color_scheme(libadwaita::ColorScheme::Default);

        let window = ApplicationWindow::builder()
            .application(app)
            .title("OpenrowDB")
            .default_width(1100)
            .default_height(700)
            .build();

        let header = HeaderBar::new();
        let title = gtk4::Label::new(Some("OpenrowDB"));
        title.add_css_class("title");
        header.set_title_widget(Some(&title));

        let stack = ViewStack::new();
        let placeholder = gtk4::Box::builder()
            .orientation(gtk4::Orientation::Vertical)
            .spacing(12)
            .margin_top(48)
            .margin_bottom(48)
            .margin_start(48)
            .margin_end(48)
            .halign(gtk4::Align::Center)
            .valign(gtk4::Align::Center)
            .build();

        let icon = gtk4::Image::from_icon_name("database-symbolic");
        icon.set_pixel_size(64);

        let heading = gtk4::Label::new(Some("Connect to a database"));
        heading.add_css_class("title-1");

        let subtitle = gtk4::Label::new(Some(
            "Linux port initialized — GTK 4 + libadwaita.\n\
             Core crate wired; drivers and workspace UI come next.",
        ));
        subtitle.add_css_class("dim-label");
        subtitle.set_justify(gtk4::Justification::Center);

        // Prove the shared core crate links on Linux builds.
        let dialect_note = gtk4::Label::new(Some(&format!(
            "Core dialect check: {}",
            SqlDialect::Postgres.quote_identifier("users")
        )));
        dialect_note.add_css_class("caption");

        placeholder.append(&icon);
        placeholder.append(&heading);
        placeholder.append(&subtitle);
        placeholder.append(&dialect_note);

        let page = ViewStackPage::builder()
            .child(&placeholder)
            .title("Welcome")
            .build();
        stack.add(&page);

        let toolbar_view = libadwaita::ToolbarView::new();
        toolbar_view.add_top_bar(&header);
        toolbar_view.set_content(Some(&stack));

        window.set_content(Some(&toolbar_view));
        window.present();
    });

    app.run()
}
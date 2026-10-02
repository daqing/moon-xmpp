///|
/// Stream features advertised by the server after a stream header.
pub struct Features {
  starttls : Bool
  starttls_required : Bool
  mechanisms : Array[String]
  bind : Bool
} derive(Eq, Debug)

///|
pub extend Features with Eq::{not_equal, equal}

///|
pub extend Features with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Parse a `<stream:features/>` element. Feature matching is done on local
/// names; unknown features are ignored.
fn parse_features(el : @XMLParser.XMLElement) -> Features {
  let mut starttls = false
  let mut starttls_required = false
  let mechanisms : Array[String] = []
  let mut bind = false
  for child in el.get_children() {
    guard child is @XMLParser.XMLChildren::Element(feature) else { continue }
    match feature.name {
      "starttls" => {
        starttls = true
        for sub in feature.get_children() {
          guard sub is @XMLParser.XMLChildren::Element(marker) else { continue }
          if marker.name is "required" {
            starttls_required = true
          }
        }
      }
      "mechanisms" =>
        for sub in feature.get_children() {
          guard sub is @XMLParser.XMLChildren::Element(mechanism) else {
            continue
          }
          if mechanism.name is "mechanism" {
            mechanisms.push(mechanism.get_text())
          }
        }
      "bind" => bind = true
      _ => ()
    }
  }
  { starttls, starttls_required, mechanisms, bind, }
}

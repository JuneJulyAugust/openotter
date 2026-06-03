/*
  OpenOtter SATEL-VL53L8 full-carrier case, v0.

  Units: millimeters.

  This case keeps the complete SATEL carrier board intact. It is intended for
  the safer v1.2 validation path where the SATEL regulators, level translators,
  and J1/J2 carrier pads remain in the circuit.

  The ST STEP/Gerber package should be used for final dimensions. Until that is
  available, measure the real board and update board_w, board_h, board_t,
  sensor_x, and sensor_y before printing a deployment part.

  Export examples:
    openscad -D 'part="base"' -o satel_vl53l8_full_carrier_case_base.stl satel_vl53l8_full_carrier_case.scad
    openscad -D 'part="lid"'  -o satel_vl53l8_full_carrier_case_lid.stl  satel_vl53l8_full_carrier_case.scad
    openscad -D 'part="mount_plate"' -o satel_vl53l8_full_carrier_mount_plate.stl satel_vl53l8_full_carrier_case.scad
*/

part = "assembly"; // "base", "lid", "mount_plate", or "assembly"

// Approximate full-carrier dimensions. Replace with ST CAD/Gerber or caliper
// measurements before deployment.
board_w = 30.5;
board_h = 66.0;
board_t = 1.6;

// Sensor package center relative to PCB center. Positive Y points toward the
// J1/J2 header and cable-exit end.
sensor_x = 0.0;
sensor_y = -21.0;

board_clearance = 0.8;
floor_t = 1.6;
wall_t = 1.9;
lid_t = 1.5;
corner_r = 2.5;

// Full carrier can have soldered pigtails or low-profile pins near J1/J2.
component_clearance_z = 3.5;
header_clearance_z = 8.0;
header_bay_h = 18.0;

optic_opening = 18.0;
cable_slot_w = 13.0;
cable_slot_z = 4.0;
strain_bar_w = 18.0;
strain_bar_h = 2.6;

// Board retention and harness strain relief. The board is held by printed edge
// rails plus lid pads. The board itself is not drilled or screwed.
edge_rail_w = 0.8;
edge_rail_h = 1.2;
edge_stop_h = 1.2;
retainer_pad_w = 4.0;
retainer_pad_l = 7.0;
retainer_pad_h = 0.9;
tie_slot_w = 2.0;
tie_slot_l = 8.0;

ear_w = 7.0;
ear_h = 18.0;
screw_d = 2.4;
screw_head_d = 4.7;

inner_w = board_w + 2 * board_clearance;
inner_h = board_h + 2 * board_clearance;
outer_w = inner_w + 2 * wall_t;
outer_h = inner_h + 2 * wall_t;
body_z = floor_t + board_t + max(component_clearance_z, header_clearance_z);

$fn = 48;

module rounded_rect_2d(w, h, r) {
  offset(r = r) {
    square([w - 2 * r, h - 2 * r], center = true);
  }
}

module rounded_box(w, h, z, r) {
  linear_extrude(height = z) {
    rounded_rect_2d(w, h, r);
  }
}

module side_ears(z) {
  for (x = [-(outer_w / 2 + ear_w / 2 - 0.05), (outer_w / 2 + ear_w / 2 - 0.05)]) {
    translate([x, 0, 0]) {
      rounded_box(ear_w, ear_h, z, 1.8);
    }
  }
}

module screw_holes(z_extra = 1) {
  for (x = [-(outer_w / 2 + ear_w / 2), (outer_w / 2 + ear_w / 2)]) {
    translate([x, 0, -z_extra / 2]) {
      cylinder(d = screw_d, h = body_z + lid_t + z_extra);
    }
  }
}

module screw_head_relief() {
  for (x = [-(outer_w / 2 + ear_w / 2), (outer_w / 2 + ear_w / 2)]) {
    translate([x, 0, body_z - 1.0]) {
      cylinder(d = screw_head_d, h = 1.4);
    }
  }
}

module harness_tie_slots() {
  for (x = [-strain_bar_w / 2 - 2.0, strain_bar_w / 2 + 2.0]) {
    translate([x, outer_h / 2 - wall_t - 5.0, -0.2]) {
      cube([tie_slot_w, tie_slot_l, floor_t + 0.6], center = true);
    }
  }
}

module board_cavity() {
  translate([0, 0, floor_t]) {
    rounded_box(inner_w, inner_h, body_z + 0.6, 1.0);
  }
}

module header_service_relief() {
  translate([0, inner_h / 2 - header_bay_h / 2, floor_t + board_t + header_clearance_z / 2]) {
    cube([inner_w, header_bay_h, header_clearance_z + 0.5], center = true);
  }
}

module cable_exit_slot() {
  translate([0, outer_h / 2 + 0.1, floor_t + cable_slot_z / 2]) {
    cube([cable_slot_w, wall_t + 0.5, cable_slot_z], center = true);
  }
}

module base() {
  difference() {
    union() {
      rounded_box(outer_w, outer_h, body_z, corner_r);
      side_ears(body_z);

      // Raised rear strain bar for a zip tie or heat-shrink wrap around the
      // soldered pigtail bundle.
      translate([0, outer_h / 2 - wall_t - 2.0, floor_t + 0.9]) {
        cube([strain_bar_w, strain_bar_h, strain_bar_h], center = true);
      }
    }

    board_cavity();
    header_service_relief();
    cable_exit_slot();
    harness_tie_slots();
    screw_holes(1);
    screw_head_relief();
  }

  // Edge ledges keep the board from floating while avoiding pressure on
  // components and soldered wires.
  for (x = [-(inner_w / 2 - 2.2), (inner_w / 2 - 2.2)]) {
    for (y = [-(inner_h / 2 - 4.0), (inner_h / 2 - 4.0)]) {
      translate([x, y, floor_t]) {
        cube([2.4, 5.0, 0.9], center = true);
      }
    }
  }

  // Side rails and end stops keep the full carrier from sliding when the car
  // vibrates. They intentionally avoid the J1/J2 header service bay.
  for (x = [-(board_w / 2 + board_clearance / 2), (board_w / 2 + board_clearance / 2)]) {
    translate([x, -header_bay_h / 2 - 4.0, floor_t + edge_rail_h / 2]) {
      cube([edge_rail_w, board_h - header_bay_h - 8.0, edge_rail_h], center = true);
    }
  }

  translate([0, -board_h / 2 - board_clearance / 2, floor_t + edge_stop_h / 2]) {
    cube([board_w - 6.0, edge_rail_w, edge_stop_h], center = true);
  }
}

module lid_retainer_pads() {
  for (x = [-(board_w / 2 - 3.0), (board_w / 2 - 3.0)]) {
    for (y = [-(board_h / 2 - 8.0), (board_h / 2 - header_bay_h - 5.0)]) {
      translate([x, y, -retainer_pad_h / 2]) {
        cube([retainer_pad_w, retainer_pad_l, retainer_pad_h], center = true);
      }
    }
  }
}

module lid() {
  difference() {
    union() {
      rounded_box(outer_w, outer_h, lid_t, corner_r);
      side_ears(lid_t);

      // Shallow lip indexes into the base.
      translate([0, 0, -0.55]) {
        difference() {
          rounded_box(inner_w - 0.6, inner_h - 0.6, 0.6, 1.0);
          rounded_box(inner_w - 3.4, inner_h - 3.4, 0.8, 0.8);
        }
      }

      // These pads lightly capture the PCB edges when the lid is screwed to
      // the base. If a real board has components at these positions, reduce
      // or remove the pads before printing.
      lid_retainer_pads();
    }

    translate([sensor_x, sensor_y, -0.2]) {
      rounded_box(optic_opening, optic_opening, lid_t + 1.0, 1.2);
    }

    translate([0, outer_h / 2 + 0.1, 0.7]) {
      cube([cable_slot_w, wall_t + 0.5, 2.2], center = true);
    }

    screw_holes(1);
  }
}

module fov_preview() {
  // Preview-only 65 degree diagonal field of view. Keep bumpers, tape, screws,
  // and cable loops outside this volume.
  color([0.0, 0.75, 1.0, 0.22]) {
    translate([sensor_x, sensor_y, body_z + lid_t + 1.0]) {
      cylinder(h = 38.0, d1 = optic_opening, d2 = 55.0);
    }
  }
}

module harness_preview() {
  colors = [
    [0.90, 0.05, 0.05, 1.0],
    [0.02, 0.02, 0.02, 1.0],
    [0.15, 0.20, 0.90, 1.0],
    [0.00, 0.55, 0.15, 1.0],
    [0.95, 0.75, 0.05, 1.0]
  ];
  for (i = [0:4]) {
    color(colors[i]) {
      translate([-4.8 + i * 2.4, outer_h / 2 + 24.0, floor_t + 3.2]) {
        rotate([90, 0, 0]) {
          cylinder(h = 48.0, d = 1.0);
        }
      }
    }
  }
}

module car_mount_preview() {
  color([0.35, 0.35, 0.35, 0.35]) {
    translate([0, 0, -3.0]) {
      rounded_box(outer_w + 18.0, outer_h + 14.0, 2.0, 3.0);
    }
  }
}

module mount_plate() {
  plate_w = outer_w + 2 * ear_w + 8.0;
  plate_h = outer_h + 6.0;
  difference() {
    rounded_box(plate_w, plate_h, 1.8, 2.5);
    screw_holes(2);
  }
}

module board_preview() {
  color([0.0, 0.25, 0.8, 0.45]) {
    translate([0, 0, floor_t + board_t / 2]) {
      cube([board_w, board_h, board_t], center = true);
    }
  }

  color([0.02, 0.02, 0.02, 0.85]) {
    translate([sensor_x, sensor_y, floor_t + board_t + 0.9]) {
      cube([6.4, 3.0, 1.8], center = true);
    }
  }

  color([1.0, 0.8, 0.1, 0.5]) {
    translate([0, board_h / 2 - 4.0, floor_t + board_t + 1.0]) {
      cube([26.0, 5.0, 2.0], center = true);
    }
  }
}

if (part == "base") {
  base();
} else if (part == "lid") {
  lid();
} else if (part == "mount_plate") {
  mount_plate();
} else {
  car_mount_preview();
  base();
  translate([0, 0, body_z + 1.0]) {
    lid();
  }
  board_preview();
  harness_preview();
  fov_preview();
}

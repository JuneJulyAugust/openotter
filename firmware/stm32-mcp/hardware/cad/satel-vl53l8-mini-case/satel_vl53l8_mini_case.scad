/*
  OpenOtter SATEL-VL53L8 mini-PCB case, v0.

  Units: millimeters.

  This is a parametric first print for the broken-off SATEL-VL53L8 mini-PCB.
  Measure the snapped-off board with calipers and update board_w, board_h,
  board_t, sensor_x, and sensor_y before final deployment.

  Export examples:
    openscad -D 'part="base"' -o satel_vl53l8_mini_case_base.stl satel_vl53l8_mini_case.scad
    openscad -D 'part="lid"'  -o satel_vl53l8_mini_case_lid.stl  satel_vl53l8_mini_case.scad
*/

part = "assembly"; // "base", "lid", "mount_plate", or "assembly"

// Board defaults are conservative placeholders until the snapped-off PCB is
// measured. The model has generous clearance so the first print can be used as
// a fit gauge.
board_w = 20.0;
board_h = 22.0;
board_t = 1.0;

// Sensor package center relative to PCB center. Positive Y points toward the
// cable exit. Move these after checking the real mini-PCB.
sensor_x = 0.0;
sensor_y = -1.5;

board_clearance = 0.7;
component_clearance_z = 3.0;
floor_t = 1.4;
wall_t = 1.7;
lid_t = 1.4;
corner_r = 2.0;

// Larger than the 6.4 x 3.0 mm package to avoid clipping the 65 deg diagonal
// field of view and to tolerate sensor-offset error in the v0 dimensions.
optic_opening = 14.0;

// Cable bay and strain relief.
cable_bay_h = 8.0;
cable_slot_w = 10.0;
cable_slot_z = 3.0;
strain_bar_w = 14.0;
strain_bar_h = 2.4;

// Board retention and solder-pad protection. The tiny PCB is held by side
// rails plus lid pads; the soldered 30 AWG pigtails get a separate tie path.
edge_rail_w = 0.7;
edge_rail_h = 1.0;
edge_stop_h = 1.0;
retainer_pad_w = 3.0;
retainer_pad_l = 4.5;
retainer_pad_h = 0.8;
tie_slot_w = 1.8;
tie_slot_l = 6.5;

// Optional M2 screw ears.
ear_w = 6.0;
ear_h = 14.0;
screw_d = 2.4;
screw_head_d = 4.4;

inner_w = board_w + 2 * board_clearance;
inner_h = board_h + 2 * board_clearance;
outer_w = inner_w + 2 * wall_t;
outer_h = inner_h + 2 * wall_t + cable_bay_h;
body_z = floor_t + board_t + component_clearance_z;

board_center_y = -cable_bay_h / 2;
cable_center_y = outer_h / 2 - wall_t - cable_bay_h / 2;

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

module screw_holes(z_extra = 1) {
  for (x = [-(outer_w / 2 + ear_w / 2), (outer_w / 2 + ear_w / 2)]) {
    translate([x, 0, -z_extra / 2]) {
      cylinder(d = screw_d, h = body_z + lid_t + z_extra);
    }
  }
}

module ears(z) {
  for (x = [-(outer_w / 2 + ear_w / 2 - 0.05), (outer_w / 2 + ear_w / 2 - 0.05)]) {
    translate([x, 0, 0]) {
      rounded_box(ear_w, ear_h, z, 1.6);
    }
  }
}

module board_cavity() {
  translate([0, board_center_y, floor_t]) {
    rounded_box(inner_w, inner_h, body_z + 0.5, 0.8);
  }
}

module cable_cavity() {
  translate([0, cable_center_y, floor_t + (body_z + 0.5) / 2]) {
    cube([inner_w, cable_bay_h + 0.2, body_z + 0.5], center = true);
  }
}

module cable_exit_slot() {
  translate([0, outer_h / 2 + 0.1, floor_t + cable_slot_z / 2]) {
    cube([cable_slot_w, wall_t + 0.4, cable_slot_z], center = true);
  }
}

module screw_head_relief() {
  for (x = [-(outer_w / 2 + ear_w / 2), (outer_w / 2 + ear_w / 2)]) {
    translate([x, 0, body_z - 0.9]) {
      cylinder(d = screw_head_d, h = 1.2);
    }
  }
}

module harness_tie_slots() {
  for (x = [-strain_bar_w / 2 - 1.8, strain_bar_w / 2 + 1.8]) {
    translate([x, outer_h / 2 - wall_t - 4.0, -0.2]) {
      cube([tie_slot_w, tie_slot_l, floor_t + 0.6], center = true);
    }
  }
}

module base() {
  difference() {
    union() {
      rounded_box(outer_w, outer_h, body_z, corner_r);
      ears(body_z);

      // Low rear bar gives zip-tie / heat-shrink strain relief without
      // crushing the soldered pad row.
      translate([0, outer_h / 2 - wall_t - 1.1, floor_t]) {
        cube([strain_bar_w, strain_bar_h, strain_bar_h], center = true);
      }
    }

    board_cavity();
    cable_cavity();
    cable_exit_slot();
    harness_tie_slots();
    screw_holes(1);
    screw_head_relief();
  }

  // Four small PCB support ledges. They keep the board above the case floor
  // without relying on the solder joints.
  for (x = [-(inner_w / 2 - 2.0), (inner_w / 2 - 2.0)]) {
    for (y = [board_center_y - inner_h / 2 + 2.0, board_center_y + inner_h / 2 - 2.0]) {
      translate([x, y, floor_t]) {
        cube([2.2, 2.2, 0.8], center = true);
      }
    }
  }

  // Side rails and sensor-end stop protect the 0.8 x 1.6 mm solder pads from
  // becoming the mechanical retention point.
  for (x = [-(board_w / 2 + board_clearance / 2), (board_w / 2 + board_clearance / 2)]) {
    translate([x, board_center_y, floor_t + edge_rail_h / 2]) {
      cube([edge_rail_w, board_h - 4.0, edge_rail_h], center = true);
    }
  }

  translate([0, board_center_y - board_h / 2 - board_clearance / 2, floor_t + edge_stop_h / 2]) {
    cube([board_w - 5.0, edge_rail_w, edge_stop_h], center = true);
  }
}

module lid_retainer_pads() {
  for (x = [-(board_w / 2 - 2.5), (board_w / 2 - 2.5)]) {
    for (y = [board_center_y - board_h / 2 + 4.0, board_center_y + board_h / 2 - 4.0]) {
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
      ears(lid_t);

      // Inner lip drops slightly into the base to reduce side play.
      translate([0, board_center_y, -0.55]) {
        difference() {
          rounded_box(inner_w - 0.6, inner_h - 0.6, 0.6, 0.8);
          rounded_box(inner_w - 3.2, inner_h - 3.2, 0.8, 0.6);
        }
      }

      // Edge pads lightly capture the mini-PCB when the case is screwed
      // closed. Adjust or remove if real components conflict.
      lid_retainer_pads();
    }

    translate([sensor_x, board_center_y + sensor_y, -0.2]) {
      rounded_box(optic_opening, optic_opening, lid_t + 1.0, 1.0);
    }

    // Cable relief matching the base slot.
    translate([0, outer_h / 2 + 0.1, 0.7]) {
      cube([cable_slot_w, wall_t + 0.4, 2.0], center = true);
    }

    screw_holes(1);
  }
}

module fov_preview() {
  // Preview-only 65 degree diagonal field of view. Keep the car bumper, tape,
  // screw heads, and cable loops outside this volume.
  color([1.0, 0.62, 0.05, 0.24]) {
    translate([sensor_x, board_center_y + sensor_y, body_z + lid_t + 1.0]) {
      cylinder(h = 34.0, d1 = optic_opening, d2 = 45.0);
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
      translate([-4.0 + i * 2.0, outer_h / 2 + 20.0, floor_t + 2.6]) {
        rotate([90, 0, 0]) {
          cylinder(h = 40.0, d = 0.8);
        }
      }
    }
  }
}

module car_mount_preview() {
  color([0.35, 0.35, 0.35, 0.35]) {
    translate([0, 0, -2.8]) {
      rounded_box(outer_w + 16.0, outer_h + 12.0, 1.8, 2.5);
    }
  }
}

module mount_plate() {
  // Optional tape-only plate: useful if the printed case needs a larger VHB
  // footprint on a curved RC-car bumper.
  plate_w = outer_w + 2 * ear_w + 5.0;
  plate_h = outer_h + 4.0;
  difference() {
    rounded_box(plate_w, plate_h, 1.6, 2.0);
    screw_holes(2);
  }
}

module board_preview() {
  color([0.0, 0.25, 0.8, 0.45]) {
    translate([0, board_center_y, floor_t + board_t / 2]) {
      cube([board_w, board_h, board_t], center = true);
    }
  }

  color([0.02, 0.02, 0.02, 0.8]) {
    translate([sensor_x, board_center_y + sensor_y, floor_t + board_t + 0.9]) {
      cube([6.4, 3.0, 1.8], center = true);
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

import math
from typing import Any, Dict, List, Optional, Set, Tuple
from collections import deque

def get_furniture_bbox(f: Dict) -> Dict[str, float]:
    """
    Computes the Axis-Aligned Bounding Box (AABB) for a furniture object,
    projecting its rotated width and depth onto the room axes.
    """
    rot = f.get('rotationY', 0.0)
    cos_r = abs(math.cos(rot))
    sin_r = abs(math.sin(rot))
    
    # Project rotated dimensions
    w = f.get('width', 100.0) * cos_r + f.get('depth', 100.0) * sin_r
    d = f.get('width', 100.0) * sin_r + f.get('depth', 100.0) * cos_r
    
    x = f.get('x', 0.0)
    z = f.get('z', 0.0)
    
    return {
        'left': x - w / 2.0,
        'right': x + w / 2.0,
        'top': z - d / 2.0,
        'bottom': z + d / 2.0,
        'width': w,
        'depth': d
    }

class OccupancyGrid:
    def __init__(self, room_width: float, room_length: float, cell_size: float = 10.0):
        self.room_width = room_width
        self.room_length = room_length
        self.cell_size = cell_size
        self.width_cells = max(1, int(room_width / cell_size))
        self.length_cells = max(1, int(room_length / cell_size))
        
        # 0 = Free/Walkable, 1 = Obstacle
        self.grid = [[0 for _ in range(self.length_cells)] for _ in range(self.width_cells)]

    def to_cell(self, x: float, z: float) -> Tuple[int, int]:
        i = max(0, min(self.width_cells - 1, int(x / self.cell_size)))
        j = max(0, min(self.length_cells - 1, int(z / self.cell_size)))
        return i, j

    def to_coords(self, i: int, j: int) -> Tuple[float, float]:
        x = (i + 0.5) * self.cell_size
        z = (j + 0.5) * self.cell_size
        return x, z

    def mark_obstacle_rect(self, left: float, right: float, top: float, bottom: float, padding: float = 0.0):
        # Apply padding (e.g. for clearance)
        i_start, j_start = self.to_cell(left - padding, top - padding)
        i_end, j_end = self.to_cell(right + padding, bottom + padding)
        
        for i in range(i_start, i_end + 1):
            for j in range(j_start, j_end + 1):
                self.grid[i][j] = 1

    def is_valid_cell(self, i: int, j: int) -> bool:
        return 0 <= i < self.width_cells and 0 <= j < self.length_cells

    def is_walkable(self, i: int, j: int) -> bool:
        return self.is_valid_cell(i, j) and self.grid[i][j] == 0

def find_path_astar(grid: OccupancyGrid, start: Tuple[int, int], goal: Tuple[int, int]) -> Optional[List[Tuple[int, int]]]:
    """
    Implements the standard A* Pathfinding Algorithm on the OccupancyGrid.
    """
    if not grid.is_valid_cell(start[0], start[1]) or not grid.is_valid_cell(goal[0], goal[1]):
        return None
        
    # Open list contains nodes to be evaluated: (f_score, cell)
    # Using a simple list here for standard compatibility
    open_set: Set[Tuple[int, int]] = {start}
    closed_set: Set[Tuple[int, int]] = set()
    
    came_from: Dict[Tuple[int, int], Tuple[int, int]] = {}
    
    g_score: Dict[Tuple[int, int], float] = {start: 0.0}
    
    # Manhattan distance heuristic
    def heuristic(a: Tuple[int, int], b: Tuple[int, int]) -> float:
        return abs(a[0] - b[0]) + abs(a[1] - b[1])

    f_score: Dict[Tuple[int, int], float] = {start: heuristic(start, goal)}
    
    # 8-way movement directions
    directions = [
        (0, 1), (1, 0), (0, -1), (-1, 0),   # Orthogonal
        (1, 1), (1, -1), (-1, 1), (-1, -1)   # Diagonal (cost sqrt(2))
    ]
    
    while open_set:
        # Find node in open_set with lowest f_score
        current = min(open_set, key=lambda node: f_score.get(node, float('inf')))
        
        if current == goal:
            # Reconstruct path
            path = [current]
            while current in came_from:
                current = came_from[current]
                path.append(current)
            path.reverse()
            return path
            
        open_set.remove(current)
        closed_set.add(current)
        
        for dx, dy in directions:
            neighbor = (current[0] + dx, current[1] + dy)
            
            if not grid.is_walkable(neighbor[0], neighbor[1]) or neighbor in closed_set:
                continue
                
            # Diagonal cost is 1.414, orthogonal cost is 1.0
            movement_cost = 1.414 if (dx != 0 and dy != 0) else 1.0
            tentative_g_score = g_score[current] + movement_cost
            
            if neighbor not in open_set:
                open_set.add(neighbor)
            elif tentative_g_score >= g_score.get(neighbor, float('inf')):
                continue
                
            came_from[neighbor] = current
            g_score[neighbor] = tentative_g_score
            f_score[neighbor] = tentative_g_score + heuristic(neighbor, goal)
            
    return None

def compute_reachability(grid: OccupancyGrid, start: Tuple[int, int]) -> Set[Tuple[int, int]]:
    """
    Computes all reachable walkable cells from the starting cell using BFS flood-fill.
    """
    if not grid.is_walkable(start[0], start[1]):
        return set()
        
    queue = deque([start])
    reachable = {start}
    
    directions = [(0, 1), (1, 0), (0, -1), (-1, 0)]
    
    while queue:
        current = queue.popleft()
        for dx, dy in directions:
            neighbor = (current[0] + dx, current[1] + dy)
            if grid.is_walkable(neighbor[0], neighbor[1]) and neighbor not in reachable:
                reachable.add(neighbor)
                queue.append(neighbor)
                
    return reachable


# ==========================================
# 2D OBB (ORIENTED BOUNDING BOX) GEOMETRY
# ==========================================

class OBB2D:
    def __init__(self, cx: float, cz: float, width: float, depth: float, rotation: float):
        """
        cx, cz: Center of the bounding box (in cm)
        width: Size along the local X axis (in cm)
        depth: Size along the local Z axis (in cm)
        rotation: Rotation around Y axis in radians
        """
        self.cx = cx
        self.cz = cz
        self.width = width
        self.depth = depth
        self.rotation = rotation

        # Local axes (directional vectors)
        cos_r = math.cos(rotation)
        sin_r = math.sin(rotation)
        
        self.axis_x = (cos_r, -sin_r) # Local X axis projected to global (X, Z)
        self.axis_z = (sin_r, cos_r)  # Local Z axis projected to global (X, Z)
        
        # Extents (half dimensions)
        self.ext_x = width / 2.0
        self.ext_z = depth / 2.0

    def get_corners(self) -> List[Tuple[float, float]]:
        """
        Returns the 4 corners of the OBB in global (X, Z) space.
        """
        corners = []
        # Relative vectors for local corners
        dx = self.axis_x
        dz = self.axis_z
        
        for sx in [-1, 1]:
            for sz in [-1, 1]:
                x = self.cx + sx * self.ext_x * dx[0] + sz * self.ext_z * dz[0]
                z = self.cz + sx * self.ext_x * dx[1] + sz * self.ext_z * dz[1]
                corners.append((x, z))
                
        # Return corners in counter-clockwise / standard order
        return [corners[0], corners[1], corners[3], corners[2]]


def get_furniture_obb(f: Dict) -> OBB2D:
    """
    Constructs an OBB2D representation for a furniture dictionary object.
    """
    return OBB2D(
        cx=f.get('x', 0.0),
        cz=f.get('z', 0.0),
        width=f.get('width', 100.0),
        depth=f.get('depth', 100.0),
        rotation=f.get('rotationY', 0.0)
    )


def project_points(points: List[Tuple[float, float]], axis: Tuple[float, float]) -> Tuple[float, float]:
    """
    Projects list of points onto a 2D axis. Returns min and max projections.
    """
    dots = [p[0] * axis[0] + p[1] * axis[1] for p in points]
    return min(dots), max(dots)


def obb_overlap_sat(obb1: OBB2D, obb2: OBB2D) -> Tuple[bool, float, Tuple[float, float]]:
    """
    Tests if two OBB2D boxes overlap using the Separating Axis Theorem (SAT).
    Returns:
        - has_overlap (bool)
        - penetration_depth (float)
        - separation_axis (Tuple[float, float])
    """
    # Potential separating axes are the face normals (axes) of both boxes
    axes = [
        obb1.axis_x,
        obb1.axis_z,
        obb2.axis_x,
        obb2.axis_z
    ]
    
    corners1 = obb1.get_corners()
    corners2 = obb2.get_corners()
    
    min_overlap = float('inf')
    push_axis = (0.0, 0.0)
    
    for axis in axes:
        # Normalize axis
        length = math.sqrt(axis[0]**2 + axis[1]**2)
        if length == 0:
            continue
        norm_axis = (axis[0] / length, axis[1] / length)
        
        min1, max1 = project_points(corners1, norm_axis)
        min2, max2 = project_points(corners2, norm_axis)
        
        # Check overlap
        if max1 < min2 or max2 < min1:
            return False, 0.0, (0.0, 0.0) # Separating axis found
            
        # Calculate overlap length
        overlap = min(max1, max2) - max(min1, min2)
        if overlap < min_overlap:
            min_overlap = overlap
            push_axis = norm_axis
            
    # If we get here, no separating axis was found, so there is an overlap
    return True, min_overlap, push_axis


# ==========================================
# PROCEDURAL ROOM GEOMETRY GENERATOR
# ==========================================

def generate_room_geometry(
    room_width: float,
    room_length: float,
    num_doors: int,
    num_windows: int,
    wall_thickness: float = 20.0
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """
    Generates 4 walls and distributes doors and windows deterministically along walls.
    Arguments:
        room_width: Room dimension along X axis (in cm)
        room_length: Room dimension along Z axis (in cm)
        num_doors: Number of doors to place
        num_windows: Number of windows to place
        wall_thickness: Thickness of walls (in cm, default 20)
    Returns:
        walls: List of Dicts with keys x1, y1 (Z1), x2, y2 (Z2), thickness
        openings: List of Dicts with keys id, type, x, y (Z), width, angle
    """
    # 1. Procedural Wall Generation
    # North Wall (y=0), East Wall (x=width), South Wall (y=length), West Wall (x=0)
    walls = [
        {"x1": 0.0, "y1": 0.0, "x2": room_width, "y2": 0.0, "thickness": wall_thickness}, # North
        {"x1": room_width, "y1": 0.0, "x2": room_width, "y2": room_length, "thickness": wall_thickness}, # East
        {"x1": room_width, "y1": room_length, "x2": 0.0, "y2": room_length, "thickness": wall_thickness}, # South
        {"x1": 0.0, "y1": room_length, "x2": 0.0, "y2": 0.0, "thickness": wall_thickness}  # West
    ]
    
    # 2. Openings Distribution
    openings = []
    
    # Map wall indices to assignments
    # Doors assignments order: South (2), West (3), East (1), North (0)
    door_walls = [2, 3, 1, 0]
    # Windows assignments order: North (0), East (1), West (3), South (2)
    window_walls = [0, 1, 3, 2]
    
    # Wall opening queues: wall_index -> list of (type, width)
    wall_openings_map = {0: [], 1: [], 2: [], 3: []}
    
    # Queue up doors
    for d in range(num_doors):
        w_idx = door_walls[d % 4]
        wall_openings_map[w_idx].append(("door", 90.0)) # standard door 90cm
        
    # Queue up windows
    for w in range(num_windows):
        w_idx = window_walls[w % 4]
        wall_openings_map[w_idx].append(("window", 120.0)) # standard window 120cm
        
    # Process each wall to compute coordinates
    opening_counter = 1
    for w_idx, items in wall_openings_map.items():
        if not items:
            continue
        k = len(items)
        for i, (op_type, op_width) in enumerate(items):
            # Calculate fractional position along the wall
            fraction = (i + 1) / (k + 1)
            
            x, y, angle = 0.0, 0.0, 0.0
            
            if w_idx == 0: # North wall (horizontal, y=0)
                x = fraction * room_width
                y = 0.0
                angle = 0.0
            elif w_idx == 1: # East wall (vertical, x=room_width)
                x = room_width
                y = fraction * room_length
                angle = math.pi / 2.0
            elif w_idx == 2: # South wall (horizontal, y=room_length)
                x = fraction * room_width
                y = room_length
                angle = 0.0
            elif w_idx == 3: # West wall (vertical, x=0)
                x = 0.0
                y = fraction * room_length
                angle = math.pi / 2.0
                
            openings.append({
                "id": f"opening_{op_type}_{opening_counter}",
                "type": op_type,
                "x": float(round(x, 1)),
                "y": float(round(y, 1)),
                "width": op_width,
                "angle": float(round(angle, 4))
            })
            opening_counter += 1
            
    return walls, openings


def closest_point_on_obb(obb: OBB2D, p: Tuple[float, float]) -> Tuple[float, float]:
    """
    Computes the closest 2D point on the boundary or interior of the OBB to point p.
    """
    dx = p[0] - obb.cx
    dz = p[1] - obb.cz
    
    # Project onto OBB local axes
    proj_x = dx * obb.axis_x[0] + dz * obb.axis_x[1]
    proj_z = dx * obb.axis_z[0] + dz * obb.axis_z[1]
    
    # Clamp to extents
    clamped_x = max(-obb.ext_x, min(obb.ext_x, proj_x))
    clamped_z = max(-obb.ext_z, min(obb.ext_z, proj_z))
    
    # Convert back to global coordinates
    gx = obb.cx + clamped_x * obb.axis_x[0] + clamped_z * obb.axis_z[0]
    gz = obb.cz + clamped_x * obb.axis_x[1] + clamped_z * obb.axis_z[1]
    return (gx, gz)


def mark_obstacle_obb(grid: OccupancyGrid, obb: OBB2D, padding: float = 0.0):
    """
    Marks cells within the rotated OBB as obstacles in the OccupancyGrid.
    """
    cos_r = abs(obb.axis_x[0])
    sin_r = abs(obb.axis_x[1])
    
    # Project rotated dimensions with padding
    w = (obb.width + 2 * padding) * cos_r + (obb.depth + 2 * padding) * sin_r
    d = (obb.width + 2 * padding) * sin_r + (obb.depth + 2 * padding) * cos_r
    
    left = obb.cx - w / 2.0
    right = obb.cx + w / 2.0
    top = obb.cz - d / 2.0
    bottom = obb.cz + d / 2.0
    
    i_start, j_start = grid.to_cell(left, top)
    i_end, j_end = grid.to_cell(right, bottom)
    
    for i in range(i_start, i_end + 1):
        for j in range(j_start, j_end + 1):
            cx, cz = grid.to_coords(i, j)
            
            # Vector from OBB center to cell center
            dx = cx - obb.cx
            dz = cz - obb.cz
            
            # Project onto local axes
            proj_x = dx * obb.axis_x[0] + dz * obb.axis_x[1]
            proj_z = dx * obb.axis_z[0] + dz * obb.axis_z[1]
            
            if abs(proj_x) <= (obb.ext_x + padding) and abs(proj_z) <= (obb.ext_z + padding):
                grid.grid[i][j] = 1


# ==========================================
# DISTANCE & CLEARANCE COMPUTATIONAL GEOMETRY
# ==========================================

def point_segment_distance(
    px: float, pz: float,
    ax: float, az: float,
    bx: float, bz: float
) -> Tuple[float, Tuple[float, float]]:
    """
    Computes the shortest Euclidean distance from point (px, pz) to segment (ax, az)-(bx, bz)
    and returns (distance, (closest_x, closest_z)).
    """
    dx = bx - ax
    dz = bz - az
    l2 = dx * dx + dz * dz
    if l2 == 0.0:
        dist = math.sqrt((px - ax) ** 2 + (pz - az) ** 2)
        return dist, (ax, az)

    t = ((px - ax) * dx + (pz - az) * dz) / l2
    clamped_t = max(0.0, min(1.0, t))
    closest_x = ax + clamped_t * dx
    closest_z = az + clamped_t * dz
    dist = math.sqrt((px - closest_x) ** 2 + (pz - closest_z) ** 2)
    return dist, (closest_x, closest_z)


def segment_segment_distance(
    p1: Tuple[float, float], p2: Tuple[float, float],
    p3: Tuple[float, float], p4: Tuple[float, float]
) -> float:
    """
    Computes minimum Euclidean distance between segment (p1, p2) and segment (p3, p4).
    """
    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) > (b[1] - a[1]) * (c[0] - a[0])

    intersect = (ccw(p1, p3, p4) != ccw(p2, p3, p4)) and (ccw(p1, p2, p3) != ccw(p1, p2, p4))
    if intersect:
        return 0.0

    d1, _ = point_segment_distance(p1[0], p1[1], p3[0], p3[1], p4[0], p4[1])
    d2, _ = point_segment_distance(p2[0], p2[1], p3[0], p3[1], p4[0], p4[1])
    d3, _ = point_segment_distance(p3[0], p3[1], p1[0], p1[1], p2[0], p2[1])
    d4, _ = point_segment_distance(p4[0], p4[1], p1[0], p1[1], p2[0], p2[1])
    return min(d1, d2, d3, d4)


def obb_distance(obb1: OBB2D, obb2: OBB2D) -> float:
    """
    Calculates exact shortest Euclidean distance between two rotated OBBs.
    Returns 0.0 if the OBBs overlap.
    """
    has_overlap, _, _ = obb_overlap_sat(obb1, obb2)
    if has_overlap:
        return 0.0

    corners1 = obb1.get_corners()
    corners2 = obb2.get_corners()

    edges1 = [(corners1[k], corners1[(k + 1) % 4]) for k in range(4)]
    edges2 = [(corners2[k], corners2[(k + 1) % 4]) for k in range(4)]

    min_dist = float('inf')

    # Distance from vertices of OBB1 to edges of OBB2
    for c in corners1:
        for a, b in edges2:
            d, _ = point_segment_distance(c[0], c[1], a[0], a[1], b[0], b[1])
            if d < min_dist:
                min_dist = d

    # Distance from vertices of OBB2 to edges of OBB1
    for c in corners2:
        for a, b in edges1:
            d, _ = point_segment_distance(c[0], c[1], a[0], a[1], b[0], b[1])
            if d < min_dist:
                min_dist = d

    return min_dist


def point_in_polygon(px: float, pz: float, polygon: List[Tuple[float, float]]) -> bool:
    """
    Determines if point (px, pz) lies inside polygon using ray-casting.
    """
    n = len(polygon)
    inside = False
    p1x, p1z = polygon[0]
    for i in range(1, n + 1):
        p2x, p2z = polygon[i % n]
        if min(p1z, p2z) < pz <= max(p1z, p2z):
            if px <= max(p1x, p2x):
                if p1z != p2z:
                    xinters = (pz - p1z) * (p2x - p1x) / (p2z - p1z) + p1x
                if p1x == p2x or px <= xinters:
                    inside = not inside
        p1x, p1z = p2x, p2z
    return inside


# ==========================================
# REAL-WORLD DOOR SWING GEOMETRY
# ==========================================

class DoorSwingGeometry:
    def __init__(
        self,
        door_id: str,
        cx: float,
        cz: float,
        width: float,
        angle: float,
        room_width: float,
        room_length: float,
        hinge_side: str = "left", # "left" or "right"
        swing_inward: bool = True
    ):
        self.door_id = door_id
        self.cx = cx
        self.cz = cz
        self.width = width
        self.angle = angle # radians along wall
        self.room_width = room_width
        self.room_length = room_length
        self.hinge_side = hinge_side
        self.swing_inward = swing_inward

        # Wall tangent vector
        tx = math.cos(angle)
        tz = math.sin(angle)
        self.tangent = (tx, tz)

        # Inward room normal: points from door towards room center
        nx1 = -tz
        nz1 = tx
        # Check which normal direction points into the room interior
        mid_test_x = cx + nx1 * 30.0
        mid_test_z = cz + nz1 * 30.0
        if 0 <= mid_test_x <= room_width and 0 <= mid_test_z <= room_length:
            self.normal = (nx1, nz1)
        else:
            self.normal = (-nx1, -nz1)

        # Hinge location
        half_w = width / 2.0
        sign = -1.0 if hinge_side == "left" else 1.0
        self.hinge_x = cx + sign * half_w * tx
        self.hinge_z = cz + sign * half_w * tz

        # Latch location
        self.latch_x = cx - sign * half_w * tx
        self.latch_z = cz - sign * half_w * tz

        # Sector sweep angle
        # Closed leaf direction is from hinge towards latch
        closed_dir_x = (self.latch_x - self.hinge_x) / max(1.0, width)
        closed_dir_z = (self.latch_z - self.hinge_z) / max(1.0, width)
        self.start_angle = math.atan2(closed_dir_z, closed_dir_x)

        # Fully open door points inward along the normal
        open_dir_x = self.normal[0]
        open_dir_z = self.normal[1]
        self.end_angle = math.atan2(open_dir_z, open_dir_x)

        # Generate approximated polygon for the 90° door swing sector (fan shape)
        num_arc_pts = 9
        sector_pts = [(self.hinge_x, self.hinge_z)]
        # Normalize angle span
        angle_diff = (self.end_angle - self.start_angle)
        while angle_diff > math.pi:
            angle_diff -= 2 * math.pi
        while angle_diff < -math.pi:
            angle_diff += 2 * math.pi

        for step in range(num_arc_pts + 1):
            theta = self.start_angle + (step / float(num_arc_pts)) * angle_diff
            px = self.hinge_x + width * math.cos(theta)
            pz = self.hinge_z + width * math.sin(theta)
            sector_pts.append((px, pz))

        self.sector_polygon = sector_pts

        # Door passage threshold box (doorway rect extending into room by width/2 or min 60cm)
        thresh_depth = max(60.0, width * 0.75)
        corner_tl = (cx - half_w * tx, cz - half_w * tz)
        corner_tr = (cx + half_w * tx, cz + half_w * tz)
        corner_br = (corner_tr[0] + thresh_depth * self.normal[0], corner_tr[1] + thresh_depth * self.normal[1])
        corner_bl = (corner_tl[0] + thresh_depth * self.normal[0], corner_tl[1] + thresh_depth * self.normal[1])
        self.threshold_polygon = [corner_tl, corner_tr, corner_br, corner_bl]

    def check_obstruction(self, obb: OBB2D, required_clearance: float) -> Tuple[bool, float, str]:
        """
        Determines whether the given furniture OBB obstructs this door or its swing area.
        Returns:
            - is_obstructed (bool)
            - measured_clearance (float in cm)
            - reason (str)
        """
        corners = obb.get_corners()
        
        # 1. Check if any OBB corner is inside the door swing sector
        for cx, cz in corners:
            if point_in_polygon(cx, cz, self.sector_polygon):
                dist = math.sqrt((cx - self.hinge_x) ** 2 + (cz - self.hinge_z) ** 2)
                return True, round(dist, 1), "interferes with the door-swing arc"

        # 2. Check if any OBB corner is inside the immediate door threshold zone
        for cx, cz in corners:
            if point_in_polygon(cx, cz, self.threshold_polygon):
                dist, _ = point_segment_distance(cx, cz, self.hinge_x, self.hinge_z, self.latch_x, self.latch_z)
                return True, round(dist, 1), "blocks doorway entrance and threshold"

        # 3. Check if door hinge is inside the OBB
        if point_in_polygon(self.hinge_x, self.hinge_z, corners):
            return True, 0.0, "completely overlaps door opening hinge"

        # 4. Measure shortest distance from OBB to the door swing perimeter
        min_dist = float('inf')
        for i in range(len(self.sector_polygon) - 1):
            s1 = self.sector_polygon[i]
            s2 = self.sector_polygon[i + 1]
            for j in range(4):
                c1 = corners[j]
                c2 = corners[(j + 1) % 4]
                d = segment_segment_distance(s1, s2, c1, c2)
                if d < min_dist:
                    min_dist = d

        # Also test distance from closest point on OBB to door center
        gx, gz = closest_point_on_obb(obb, (self.cx, self.cz))
        center_dist = math.sqrt((gx - self.cx) ** 2 + (gz - self.cz) ** 2)

        effective_clearance = min(min_dist, center_dist)

        if effective_clearance < required_clearance:
            return True, round(effective_clearance, 1), "within door clearance buffer"

        return False, round(effective_clearance, 1), "clear"


def get_door_swing_geometry(
    door: Dict[str, Any],
    room_width: float,
    room_length: float
) -> DoorSwingGeometry:
    """
    Constructs a DoorSwingGeometry from a door dictionary.
    """
    return DoorSwingGeometry(
        door_id=str(door.get('id', 'door_default')),
        cx=float(door.get('x', 0.0)),
        cz=float(door.get('y', door.get('z', 0.0))),
        width=float(door.get('width', 90.0)),
        angle=float(door.get('angle', 0.0)),
        room_width=room_width,
        room_length=room_length,
        hinge_side=str(door.get('hinge', 'left')),
        swing_inward=bool(door.get('swing_inward', True))
    )


# ==========================================
# FURNITURE CLEARANCE ZONES
# ==========================================

def get_furniture_clearance_obb(
    f: Dict[str, Any],
    clearance_type: str, # "front", "rear", "left", "right"
    depth: float = 75.0
) -> OBB2D:
    """
    Generates an OBB2D representing a functional clearance zone (e.g., front of wardrobe,
    chair pullout space, bed side egress).
    """
    base_obb = get_furniture_obb(f)

    if clearance_type == "front":
        # Local +Z direction (forward)
        offset = base_obb.ext_z + depth / 2.0
        cx = base_obb.cx + offset * base_obb.axis_z[0]
        cz = base_obb.cz + offset * base_obb.axis_z[1]
        return OBB2D(cx, cz, base_obb.width, depth, base_obb.rotation)

    elif clearance_type == "rear":
        # Local -Z direction (backwards, e.g., behind chairs)
        offset = -(base_obb.ext_z + depth / 2.0)
        cx = base_obb.cx + offset * base_obb.axis_z[0]
        cz = base_obb.cz + offset * base_obb.axis_z[1]
        return OBB2D(cx, cz, base_obb.width, depth, base_obb.rotation)

    elif clearance_type == "left":
        # Local -X direction
        offset = -(base_obb.ext_x + depth / 2.0)
        cx = base_obb.cx + offset * base_obb.axis_x[0]
        cz = base_obb.cz + offset * base_obb.axis_x[1]
        return OBB2D(cx, cz, depth, base_obb.depth, base_obb.rotation)

    elif clearance_type == "right":
        # Local +X direction
        offset = base_obb.ext_x + depth / 2.0
        cx = base_obb.cx + offset * base_obb.axis_x[0]
        cz = base_obb.cz + offset * base_obb.axis_x[1]
        return OBB2D(cx, cz, depth, base_obb.depth, base_obb.rotation)

    return base_obb


def check_furniture_metadata(f: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validates whether furniture object has required physical dimensions and metadata.
    """
    missing = []
    w = f.get('width')
    d = f.get('depth')
    h = f.get('height')

    if w is None or float(w) <= 0.0:
        missing.append('width')
    if d is None or float(d) <= 0.0:
        missing.append('depth')
    if h is None or float(h) <= 0.0:
        missing.append('height')

    name = f.get('name')
    if not name or str(name).strip() == "":
        missing.append('name')

    return {
        'valid': len(missing) == 0,
        'missing': missing
    }

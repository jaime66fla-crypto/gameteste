/** Keep existing resource IDs and RNG sequence; remove only overlapping parked cars. */
export function clearOverlappingCars(resources, vehicles, clearance = 6) {
 const occupied = vehicles.map(v => v.p);
 return resources.filter(resource => {
  if (resource.kind !== 'car') return true;
  const p = resource.p;
  if (occupied.some(other => Math.hypot(p[0]-other[0],p[2]-other[2]) < clearance)) return false;
  occupied.push(p);
  return true;
 });
}

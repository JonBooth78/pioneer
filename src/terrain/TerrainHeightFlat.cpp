#include "Terrain.h"

template <>
double TerrainHeightFractal<TerrainHeightFlat>::GetHeight(const vector3d &p)
{
	return 0.0;
}

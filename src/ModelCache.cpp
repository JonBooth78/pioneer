﻿#include "ModelCache.h"
#include "newmodel/Newmodel.h"

ModelCache::ModelCache(Graphics::Renderer *r)
: m_renderer(r)
{

}

ModelCache::~ModelCache()
{
	Flush();
}

SceneGraph::NModel *ModelCache::FindModel(const std::string &name)
{
	ModelMap::iterator it = m_models.find(name);

	if (it == m_models.end()) {
		try {
			SceneGraph::Loader loader(m_renderer);
			SceneGraph::NModel *m = loader.LoadModel(name);
			m_models[name] = m;
			return m;
		} catch (SceneGraph::LoadingError &) {
			throw ModelNotFoundException();
		}
	}
	return it->second;
}

void ModelCache::Flush()
{
	for(ModelMap::iterator it = m_models.begin(); it != m_models.end(); ++it) {
		delete it->second;
	}
	m_models.clear();
}
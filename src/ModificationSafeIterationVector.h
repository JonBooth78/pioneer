#ifndef MODIFICATION_SAFE_ITERATION_VECTOR_H__Included
#define MODIFICATION_SAFE_ITERATION_VECTOR_H__Included

// Copyright © 2008-2024 Pioneer Developers. See AUTHORS.txt for details
// Licensed under the terms of the GPL v3. See licenses/GPL-3.txt


#include <vector>
#include <cassert>

// ModificationSafeIterationVector
//
// This vector looks and behaves much like a std::vector
// without reverse iteration (for now).
// however, it is safe to modify (add/remove) elements whilst iterating
// the vector, unlike std::vector.

#ifndef NDEBUG
#define _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
#endif

template <class vector>
class ModificationSafeIterationVectorConstIterator {
public:
	friend vector;

	using iterator_category = std::random_access_iterator_tag;
	using value_type = typename vector::value_type;
	using difference_type = typename vector::difference_type;
	using pointer = typename vector::const_pointer;
	using reference = const value_type &;

	ModificationSafeIterationVectorConstIterator &operator=(ModificationSafeIterationVectorConstIterator &other)
	{
		m_pos = other.m_pos;
		if (m_vec != other.m_vec) {
			m_vec->removeIterator(this);
			m_vec = other.m_vec;
			m_vec->addIterator(this);
		}
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		m_currentStart = other.m_currentStart;
		m_currentEnd = other.m_currentEnd;
#endif
		return *this;
	}

	~ModificationSafeIterationVectorConstIterator()
	{
		m_vec->removeIterator(this);
	}

	[[nodiscard]] constexpr inline reference operator*() const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos >= m_currentStart);
		assert(m_pos < *m_currentEnd);
#endif
		return *m_pos;
	}

	[[nodiscard]] constexpr inline pointer operator->() const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos >= m_currentStart);
		assert(m_pos < *m_currentEnd);
#endif
		return m_pos;
	}

	constexpr inline ModificationSafeIterationVectorConstIterator &operator++() noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos < *m_currentEnd);
#endif
		++m_pos;
		return *this;
	}

	constexpr inline ModificationSafeIterationVectorConstIterator &operator++(int) noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos < *m_currentEnd);
#endif
		++m_pos;
		return ModificationSafeIterationVectorConstIterator(m_pos - 1, m_vec);
	}

	constexpr inline ModificationSafeIterationVectorConstIterator &operator--() noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos > m_currentStart);
#endif
		--m_pos;
		return *this;
	}

	constexpr inline ModificationSafeIterationVectorConstIterator &operator--(int) noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos > m_currentStart);
#endif
		ModificationSafeIterationVectorConstIterator rv(m_pos, m_vec);
		--m_pos;
		return rv;
	}

	constexpr inline ModificationSafeIterationVectorConstIterator &operator+=(const difference_type offset) noexcept
	{
		m_pos += offset;
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos >= m_currentStart);
		assert(m_pos <= *m_currentEnd);
#endif
		return *this;
	}

	//

	[[nodiscard]] constexpr inline ModificationSafeIterationVectorConstIterator operator+(const difference_type offset) const noexcept
	{
		ModificationSafeIterationVectorConstIterator(m_pos + offset, m_vec);
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(rv.m_pos >= m_currentStart);
		assert(rv.m_pos <= *m_currentEnd);
#endif
		return rv;
	}

	[[nodiscard]] friend constexpr inline ModificationSafeIterationVectorConstIterator operator+(
		const difference_type offset, ModificationSafeIterationVectorConstIterator next) noexcept
	{
		next += offset;
		return next;
	}

	constexpr inline ModificationSafeIterationVectorConstIterator &operator-=(const difference_type offset) noexcept
	{
		this += -offset;
		return *this;
	}

	[[nodiscard]] constexpr inline ModificationSafeIterationVectorConstIterator operator-(const difference_type offset) const noexcept
	{
		ModificationSafeIterationVectorConstIterator rv(m_pos - offset, m_vec);
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(rv.m_pos >= m_currentStart);
		assert(rv.m_pos <= *m_currentEnd);
#endif
		return rv;
	}

	[[nodiscard]] constexpr inline difference_type operator-(const ModificationSafeIterationVectorConstIterator &other) const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(other.m_vec == m_vec);
#endif
		return m_pos - other.m_pos;
	}

	[[nodiscard]] constexpr inline reference operator[](const difference_type offset) const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos + offset >= m_currentStart);
		assert(m_pos + offset < *m_currentEnd);
#endif
		reference rv = *(m_pos + offset);
		return rv;
	}

	[[nodiscard]] constexpr inline bool operator==(const ModificationSafeIterationVectorConstIterator &other) const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(other.m_vec == m_vec);
#endif
		return m_pos == other.m_pos;
	}

#if _HAS_CXX20
	[[nodiscard]] constexpr strong_ordering inline operator<=>(const ModificationSafeIterationVectorConstIterator &other) const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(other.m_vec == m_vec);
#endif
		return m_pos <=> other.m_pos;
	}
#else // ^^^ _HAS_CXX20 / !_HAS_CXX20 vvv
	[[nodiscard]] constexpr inline bool operator!=(const ModificationSafeIterationVectorConstIterator &other) const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(other.m_vec == m_vec);
#endif
		return m_pos != other.m_pos;
	}

	[[nodiscard]] constexpr inline bool operator<(const ModificationSafeIterationVectorConstIterator &other) const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(other.m_vec == m_vec);
#endif
		return m_pos < other.m_pos;
	}

	[[nodiscard]] constexpr inline bool operator>(const ModificationSafeIterationVectorConstIterator &other) const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(other.m_vec == m_vec);
#endif
		return m_pos > other.m_pos;
	}

	[[nodiscard]] constexpr inline bool operator<=(const ModificationSafeIterationVectorConstIterator &other) const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(other.m_vec == m_vec);
#endif
		return m_pos <= other.m_pos;
	}

	[[nodiscard]] constexpr inline bool operator>=(const ModificationSafeIterationVectorConstIterator &other) const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(other.m_pos == m_pos);
#endif
		return m_pos >= other.m_pos;
	}
#endif
protected:
	pointer m_pos;
	const vector *m_vec;
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
	pointer m_currentStart;
	const pointer *m_currentEnd;
#endif

	ModificationSafeIterationVectorConstIterator(pointer pos, const vector *vector) :
		m_pos(pos), m_vec(vector)
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		,
		m_currentStart(&vector->m_base[0]),
		m_currentEnd(&vector->m_currentEnd)
#endif
	{
		m_vec->addIterator(this);
	}

	void rebase(difference_type offset, pointer insert_ptr, difference_type insert_size)
	{
		m_pos += offset;
		if (insert_size != 0 && m_pos >= insert_ptr) {
			m_pos += insert_size;
		}
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		m_currentStart += offset;
		assert(m_pos >= m_currentStart);
		assert(m_pos <= *m_currentEnd);
#endif
	}
};

template <class vector>
class ModificationSafeIterationVectorIterator : public ModificationSafeIterationVectorConstIterator<vector> {
public:
	friend vector;

	using base = ModificationSafeIterationVectorConstIterator<vector>;

	using iterator_category = std::random_access_iterator_tag;
	using value_type = typename vector::value_type;
	using difference_type = typename vector::difference_type;
	using pointer = typename vector::pointer;
	using const_pointer = typename vector::const_pointer;

	using reference = value_type &;

	[[nodiscard]] constexpr inline reference operator*() const noexcept
	{
		return const_cast<reference>(base::operator*());
	}

	[[nodiscard]] constexpr inline pointer operator->() const noexcept
	{
		return const_cast<pointer>(base::operator->());
	}

	inline constexpr ModificationSafeIterationVectorIterator &operator++() noexcept
	{
		base::operator++();
		return *this;
	}

	inline constexpr ModificationSafeIterationVectorIterator operator++(int) noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos < *m_currentEnd);
#endif
		ModificationSafeIterationVectorIterator rv(m_pos, m_vec);
		++m_pos;
		return rv;
	}

	inline constexpr ModificationSafeIterationVectorIterator &operator--() noexcept
	{
		base::operator--();
		return *this;
	}

	inline constexpr ModificationSafeIterationVectorIterator operator--(int) noexcept
	{
		ModificationSafeIterationVectorIterator rv(m_pos, m_vec);
		--m_pos;
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos > m_currentStart);
#endif
		return rv;
	}

	inline constexpr ModificationSafeIterationVectorIterator &operator+=(const difference_type offset) noexcept
	{
		base::operator+=(offset);
		return *this;
	}

	[[nodiscard]] constexpr inline ModificationSafeIterationVectorIterator operator+(const difference_type offset) const noexcept
	{
		ModificationSafeIterationVectorIterator rv(m_pos + offset, m_vec);
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(rv.m_pos >= m_currentStart);
		assert(rv.m_pos < *m_currentEnd);
#endif
		return rv;
	}

	[[nodiscard]] friend constexpr inline ModificationSafeIterationVectorIterator operator+(const difference_type offset, ModificationSafeIterationVectorIterator next) noexcept
	{
		next += offset;
		return next;
	}

	inline constexpr ModificationSafeIterationVectorIterator &operator-=(const difference_type offset) noexcept
	{
		base::operator-=(offset);
		return *this;
	}

	using base::operator-;

	[[nodiscard]] inline constexpr reference operator[](const difference_type offset) const noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(m_pos + offset > m_currentStart);
		assert(m_pos + offset < *m_currentEnd);
#endif
		reference rv = *(m_pos + offset);
		return rv;
	}

protected:
	ModificationSafeIterationVectorIterator(const_pointer pos, const vector *vector) :
		ModificationSafeIterationVectorConstIterator(pos, vector)
	{
	}
};

template <typename T, class Allocator = std::allocator<T>>
class ModificationSafeIterationVector {
public:
	using value_type = T;
	using allocator_type = Allocator;
	using pointer = typename std::vector<T, Allocator>::pointer;
	using const_pointer = typename std::vector<T, Allocator>::const_pointer;
	using reference = T &;
	using const_reference = const T &;
	using size_type = typename std::vector<T, Allocator>::size_type;
	using difference_type = typename std::vector<T, Allocator>::difference_type;

	using const_iterator = ModificationSafeIterationVectorConstIterator<ModificationSafeIterationVector<T, Allocator>>;
	using iterator = ModificationSafeIterationVectorIterator<ModificationSafeIterationVector<T, Allocator>>;
	friend const_iterator;
	//	typename const_iterator;

	// element access

	reference at(size_type pos)
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(pos < m_base.size());
#endif
		return m_base.at(pos);
	}
	const reference at(size_type pos) const
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(pos < m_base.size());
#endif
		return m_base.at(pos);
	}
	reference operator[](size_type pos)
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(pos >= 0);
		assert(pos < m_base.size());
#endif
		return m_base[pos];
	}

	const_reference operator[](size_type pos) const
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(pos >= 0);
		assert(pos < m_base.size());
#endif
		return m_base[pos];
	}
	reference front()
	{
		return m_base.front();
	}
	const reference front() const
	{
		return m_base.front();
	}
	reference back()
	{
		return m_base.back();
	}
	const reference back() const
	{
		return m_base.back();
	}
	T *data() noexcept
	{
		return m_base.data();
	}
	const T *data() const
	{
		return m_base.data();
	}

	// iterator
	iterator begin() noexcept
	{
		return iterator(m_base.data(), this);
	}
	const_iterator begin() const noexcept
	{
		return const_iterator(m_base.data(), this);
	}
	const_iterator cbegin() const noexcept
	{
		return const_iterator(m_base.data(), this);
	}
	iterator end() noexcept
	{
		return iterator(m_base.data() + m_base.size(), this);
	}
	const_iterator end() const noexcept
	{
		return const_iterator(m_base.data() + m_base.size(), this);
	}
	const_iterator cend() const noexcept
	{
		return const_iterator(m_base.data() + m_base.size(), this);
	}
	// No reverse iterators are defined (TODO?)

	// Capacity
	[[nodiscard]] constexpr inline bool empty() const noexcept
	{
		return m_base.empty();
	}
	constexpr inline size_type size() const noexcept
	{
		return m_base.size();
	}
	constexpr inline size_type max_size() const noexcept
	{
		return m_base.max_size();
	}
	constexpr size_type capacity() const noexcept
	{
		return m_base.capacity();
	}
	inline void reserve(size_type cap)
	{
		T *pre = m_base.data();
		m_base.reserve(cap);
		completeRealloc(pre, 0, 0);
	}
	constexpr inline void shrink_to_fit()
	{
		T *pre = m_base.data();
		m_base.shrink_to_fit();
		completeRealloc(pre, 0, 0);
	}

	// modifiers
	constexpr inline void clear() noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(iteratorCount() == 0);
#endif
		m_base.clear();
	}
	constexpr inline iterator insert(const_iterator pos, const T &val)
	{
		difference_type offset = pos.m_pos - m_base.data();
		T *pre = m_base.data();
		auto rv = m_base.insert(val);
		completeRealloc(pre, offset, 1);
		return iterator(m_base.data() + (rv - m_base.begin()));
	}

	constexpr inline iterator insert(const_iterator pos, T &&val)
	{
		difference_type offset = pos.m_pos - m_base.data();
		T *pre = m_base.data();
		auto rv = m_base.insert(val);
		completeRealloc(pre, offset, 1);
		return iterator(m_base.data() + (rv - m_base.begin()));
	}

	constexpr iterator insert(const_iterator pos, size_type count, const T &value)
	{
		difference_type offset = pos.m_pos - m_base.data();

		T *pre = m_base.data();
		auto rv = m_base.insert(m_base.begin() + offset, count, value);
		completeRealloc(pre, offset, 1);
		return iterator(m_base.data() + (rv - m_base.begin()));
	}

	template <class InputIt>
	constexpr inline iterator insert(const_iterator pos, InputIt start, InputIt last)
	{
		difference_type offset = pos.m_pos - m_base.data();
		T *pre = m_base.data();
		auto rv = m_base.insert(m_base.begin() + offset, start, last);
		completeRealloc(pre, offset, last - start);
		return iterator(m_base.data() + (rv - m_base.begin()));
	}

	constexpr iterator insert(const_iterator pos, std::initializer_list<T> ilist)
	{
		difference_type offset = pos.m_pos - m_base.data();
		T *pre = m_base.data();
		auto rv = m_base.insert(m_base.begin() + offset, ilist);
		completeRealloc(pre, offset, ilist.size());
		return iterator(m_base.data() + (rv - m_base.begin()));
	}

	template <class... Args>
	constexpr iterator emplace(const_iterator pos, Args &&...args)
	{
		difference_type offset = pos.m_pos - m_base.data();
		T *pre = m_base.data();
		auto rv = m_base.emplace(m_base.begin() + offset, args);
		completeRealloc(pre, offset, 1);
		return iterator(m_base.data() + (rv - m_base.begin()));
	}

	constexpr iterator erase(const_iterator pos)
	{
		difference_type offset = pos.m_pos - m_base.data();
		auto rv = m_base.erase(m_base.begin() + offset);
		completeRealloc(m_base.data(), offset, -1);
		return iterator(m_base.data() + (rv - m_base.begin()));
	}

	constexpr iterator erase(const_iterator first, const_iterator last)
	{
		difference_type offset = first.m_pos - m_base.data();
		auto rv = m_base.erase(m_base.begin() + offset, m_base.begin() + (last.pos - m_base.data()));
		completeRealloc(m_base.data(), offset, first - last);
		return iterator(m_base.data() + (rv - m_base.begin()));
	}

	constexpr void push_back(const T &value)
	{
		difference_type offset = m_base.size();
		T *pre = m_base.data();
		m_base.push_back(value);
		completeRealloc(pre, offset, 1);
	}

	constexpr void push_back(T &&value)
	{
		difference_type offset = m_base.size();
		T *pre = m_base.data();
		m_base.push_back(value);
		completeRealloc(pre, offset, 1);
	}
	template <class... Args>
	constexpr reference emplace_back(Args &&...args)
	{
		difference_type offset = m_base.size();
		T *pre = m_base.data();
		m_base.emplace_back(args);
		completeRealloc(pre, offset, 1);
	}
	constexpr void pop_back()
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(!m_base.empty());
#endif
		T *pre = m_base.data(); // note, this can move in the event we get to zero size.
		m_base.pop_back();
		completeRealloc(pre, m_base.size(), -1);
	}

	constexpr void resize(size_type count)
	{
		size_type initial_size = m_base.size();
		if (count == initial_size) {
			return;
		}
		T *pre = m_base.data();

		if (count > initial_size) {
			difference_type offset = m_base.size();
			m_base.resize(count);
			completeRealloc(pre, offset, m_base.size() - initial_size);
		} else {
			m_base.resize(count);
			difference_type offset = m_base.size();
			completeRealloc(pre, offset, m_base.size() - initial_size);
		}
	}
	constexpr void resize(size_type count, const value_type &value)
	{
		size_type initial_size = m_base.size();
		if (count == initial_size) {
			return;
		}
		T *pre = m_base.data();

		if (count > initial_size) {
			difference_type offset = m_base.size();
			m_base.resize(count, value);
			completeRealloc(pre, offset, m_base.size() - initial_size);
		} else {
			m_base.resize(count, value);
			difference_type offset = m_base.size();
			completeRealloc(pre, offset, m_base.size() - initial_size);
		}
	}

	template <typename v>
	constexpr void swap(v &other) noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(iteratorCount() == 0);
#endif
		m_base.swap(other);
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		m_currentEnd = m_base.data() + m_base.size();
#endif
	}
	constexpr void swap(ModificationSafeIterationVector<T> &other) noexcept
	{
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		assert(iteratorCount() == 0);
#endif
		other.swap(m_base);
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		m_currentEnd = m_base.data() + m_base.size();
#endif
	}

protected:
	inline size_t iteratorCount()
	{
		size_t s = 0;
		for (auto i : m_iterators) {
			if (*i != nullptr) {
				++s;
			}
		}
		return s;
	}

	inline void completeRealloc(T *preStart, difference_type insert_pos, difference_type insert_size)
	{
		size_type newSize = m_base.size();
		pointer newStart = newSize > 0 ? m_base.data() : nullptr;
		difference_type offset = newStart - preStart;
		if (offset == 0 && insert_size == 0) {
			// no alloc happened
			return;
		}

#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
		if (offset != 0) {
			m_currentStart = newStart;
			m_currentEnd = m_currentStart + newSize;
		}
		m_currentEnd += insert_size;
#endif

		pointer insert_ptr = newStart + insert_pos;

		for (auto i : m_iterators) {
			if (i != nullptr) {
				i->rebase(offset, insert_ptr, insert_size);
			}
		}
	}

	void addIterator(const_iterator *it) const
	{
		m_iterators.push_back(it);
	}

	void removeIterator(const_iterator *it) const
	{
		for (auto &i : m_iterators) {
			if (i == it) {
				i = nullptr;
			}
		}

		// note: holes are never emptied, we just shrink at the end.
		while (!m_iterators.empty() && m_iterators.back() == nullptr) {
			m_iterators.pop_back();
		}
	}

	std::vector<T> m_base;
	mutable std::vector<const_iterator *> m_iterators;
#ifdef _MODIFICATION_SAFE_ITERATION_VECTOR_BOUNDS_CHECKING
	pointer m_currentStart;
	pointer m_currentEnd;
#endif
};


#endif MODIFICATION_SAFE_ITERATION_VECTOR_H__Included
